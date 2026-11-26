import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'tool_controller.dart';

class AxNode {
  AxNode(Map<String, Object?> form, [this.parent])
    : actor = form.str('actor'),
      name = form.str('name'),
      role = form.str('role'),
      childCount = form.integer('childCount');

  final String actor;
  final String name;
  final String role;
  final int childCount;
  final AxNode? parent;
  List<AxNode>? children;

  int get depth => parent == null ? 0 : parent!.depth + 1;
}

/// Something about the page that makes it harder to use.
class AccessibilityIssue {
  const AccessibilityIssue(this.category, this.message, this.path);
  final String category;
  final String message;

  /// The element's place: the index of each step among its parent's elements,
  /// from the root element.
  final List<int> path;
}

class AccessibilityController extends ToolController {
  AccessibilityController(super.session);

  AxNode? root;
  AxNode? selected;
  Map<String, Object?> properties = const {};
  List<(String, String)> relations = const [];
  final Set<String> expanded = {};
  bool loading = false;
  bool _wanted = false;
  String error = '';

  List<AccessibilityIssue>? issues;
  bool checking = false;

  /// The panel is on screen, so there is a tree worth having.
  void activate() {
    _wanted = true;
    if (root == null && !loading) refresh();
  }

  @override
  void onTargetDestroyed() {
    root = null;
    selected = null;
    properties = const {};
    expanded.clear();
    issues = null;
    loading = false;
    changed();
  }

  @override
  void onDocumentComplete() {
    if (_wanted) refresh();
  }

  Future<void> refresh() async {
    final actor = session.target?.accessibilityActor;
    if (actor == null) return;
    loading = true;
    error = '';
    changed();
    try {
      final walker = (await session.connection.request(
        actor,
        'getWalker',
        const {},
        const Duration(seconds: 6),
      )).obj('walker').str('actor');
      final response = await session.connection.request(walker, 'children');
      if (session.target?.accessibilityActor != actor) return;
      final forms = response.maps('children');
      root = forms.isEmpty ? null : AxNode(forms.first);
      selected = null;
      properties = const {};
      expanded.clear();
      if (root case final node?) {
        await expand(node);
        for (final child in node.children ?? const <AxNode>[]) {
          await expand(child);
        }
      }
    } on RdpError catch (failure) {
      if (!failure.isClosed) {
        error = 'The accessibility tree is not available yet.';
      }
    }
    loading = false;
    changed();
  }

  Future<void> expand(AxNode node) async {
    expanded.add(node.actor);
    if (node.children != null || node.childCount == 0) {
      changed();
      return;
    }
    try {
      final response = await session.connection.request(node.actor, 'children');
      node.children = [
        for (final child in response.maps('children')) AxNode(child, node),
      ];
    } on RdpError {
      expanded.remove(node.actor);
    }
    changed();
  }

  void collapse(AxNode node) {
    expanded.remove(node.actor);
    changed();
  }

  List<AxNode> get visibleNodes {
    final nodes = <AxNode>[];
    void visit(AxNode node) {
      nodes.add(node);
      if (!expanded.contains(node.actor)) return;
      for (final child in node.children ?? const <AxNode>[]) {
        visit(child);
      }
    }

    if (root case final node?) visit(node);
    return nodes;
  }

  Future<void> select(AxNode node) async {
    selected = node;
    properties = const {};
    relations = const [];
    changed();
    try {
      final response = await session.connection.request(node.actor, 'hydrate');
      if (selected != node) return;
      properties = response.obj('properties');
      changed();
      final related = await session.connection.request(
        node.actor,
        'getRelations',
      );
      if (selected != node) return;
      relations = [
        for (final relation in related.maps('relations'))
          for (final target in relation.maps('targets'))
            (
              relation.str('type'),
              [target.str('role'), if (target.str('name').isNotEmpty) '"${target.str('name')}"'].join(' '),
            ),
      ];
      changed();
    } on RdpError {
      // The tree changed under us.
    }
  }

  /// Looks the page over for common problems. The engine has no audit of its
  /// own, so this runs in the page.
  Future<void> checkForIssues() async {
    checking = true;
    changed();
    try {
      final result = await session.runInPage(_audit);
      issues = [
        if (result is List)
          for (final issue in result)
            if (issue is Map<String, Object?>)
              AccessibilityIssue(
                issue.str('category'),
                issue.str('message'),
                [
                  for (final step in issue.list('path'))
                    if (step is num) step.toInt(),
                ],
              ),
      ];
    } catch (failure) {
      error = '$failure';
      issues = const [];
    }
    checking = false;
    changed();
  }

  void clearIssues() {
    issues = null;
    changed();
  }

  static const String _audit = r'''
const issues = [];
const pathOf = element => {
  const path = [];
  for (let node = element; node && node !== document.documentElement; node = node.parentElement) {
    if (!node.parentElement) break;
    path.unshift(Array.prototype.indexOf.call(node.parentElement.children, node));
  }
  return path;
};
const report = (category, message, element) => {
  if (issues.length < 300) issues.push({ category, message, path: pathOf(element) });
};
const named = element => (element.textContent || '').trim() || element.getAttribute('aria-label') ||
  element.getAttribute('aria-labelledby') || element.getAttribute('title') ||
  element.querySelector('img[alt]:not([alt=""])');
if (!document.documentElement.getAttribute('lang')) report('Text Labels', 'Document should have a lang attribute.', document.documentElement);
if (!document.title.trim()) report('Text Labels', 'Document must have a title.', document.documentElement);
for (const image of document.querySelectorAll('img:not([alt])')) report('Text Labels', 'Content with images must be labeled with an alt attribute.', image);
for (const button of document.querySelectorAll('button, [role=button]')) if (!named(button)) report('Text Labels', 'Buttons should have a label.', button);
for (const link of document.querySelectorAll('a[href]')) if (!named(link)) report('Text Labels', 'Links should have an accessible name.', link);
for (const field of document.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=reset]), select, textarea')) {
  const labelled = (field.labels && field.labels.length) || field.getAttribute('aria-label') ||
    field.getAttribute('aria-labelledby') || field.getAttribute('title');
  if (!labelled) report('Text Labels', 'Form elements should have a visible text label.', field);
}
for (const frame of document.querySelectorAll('iframe:not([title])')) report('Text Labels', 'Frames should have a title.', frame);
for (const element of document.querySelectorAll('[tabindex]')) if (Number(element.getAttribute('tabindex')) > 0) report('Keyboard', 'Avoid using a tabindex attribute greater than zero.', element);
for (const element of document.querySelectorAll('[onclick]')) {
  if (!element.matches('a[href], button, input, select, textarea, summary, [tabindex]')) report('Keyboard', 'Clickable elements must be focusable and should have interactive semantics.', element);
}
const parse = color => { const m = color.match(/[\d.]+/g); return m ? m.map(Number) : null; };
const luminance = rgb => { const c = rgb.slice(0, 3).map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
let checked = 0;
for (const element of document.querySelectorAll('body *')) {
  if (checked > 600) break;
  if (!Array.prototype.some.call(element.childNodes, n => n.nodeType === 3 && n.textContent.trim())) continue;
  checked++;
  const style = getComputedStyle(element);
  if (style.visibility === 'hidden' || style.display === 'none') continue;
  const text = parse(style.color);
  let background = null;
  for (let node = element; node; node = node.parentElement) {
    const value = parse(getComputedStyle(node).backgroundColor);
    if (value && (value.length < 4 || value[3] > 0.5)) { background = value; break; }
  }
  if (!background) background = [255, 255, 255];
  if (!text) continue;
  const a = luminance(text), b = luminance(background);
  const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  const large = parseFloat(style.fontSize) >= 24 || (parseFloat(style.fontSize) >= 18.66 && Number(style.fontWeight) >= 700);
  if (ratio < (large ? 3 : 4.5)) report('Contrast', 'Text contrast ' + ratio.toFixed(2) + ' is below the recommended ' + (large ? '3' : '4.5') + '.', element);
}
return issues;
''';
}
