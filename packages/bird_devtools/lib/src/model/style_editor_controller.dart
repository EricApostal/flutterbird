import 'dart:async';
import 'dart:convert';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'tool_controller.dart';

class StyleSheetInfo {
  StyleSheetInfo({
    required this.resourceId,
    required this.href,
    required this.documentHref,
    required this.ruleCount,
    required this.isSystem,
    required this.title,
    required this.inlineOrdinal,
    this.isNew = false,
  });

  final String resourceId;

  /// Empty for a `<style>` element.
  final String href;
  final String documentHref;
  int ruleCount;
  final bool isSystem;
  final String title;

  /// Which of the page's `<style>` sheets it is, counting from zero.
  final int inlineOrdinal;
  final bool isNew;

  bool disabled = false;
  String? text;

  /// The text as the page had it, to know whether it was edited.
  String? originalText;
  String error = '';

  bool get isModified => text != null && text != originalText;

  String get name {
    if (isNew) return '<new style sheet #${inlineOrdinal + 1}>';
    if (href.isEmpty) return '<inline style sheet #${inlineOrdinal + 1}>';
    final uri = Uri.tryParse(href);
    final segments = uri?.pathSegments.where((part) => part.isNotEmpty);
    return segments == null || segments.isEmpty ? href : segments.last;
  }
}

class StyleEditorController extends ToolController {
  StyleEditorController(super.session);

  final List<StyleSheetInfo> sheets = [];
  StyleSheetInfo? selected;
  Timer? _applyTimer;
  int _newSheets = 0;

  /// Counts up when a sheet's text changes from elsewhere than the editor.
  int textRevision = 0;

  @override
  void onTargetDestroyed() {
    _applyTimer?.cancel();
    sheets.clear();
    selected = null;
    _newSheets = 0;
    changed();
  }

  @override
  void onResources(String type, List<Map<String, Object?>> resources) {
    if (type != 'stylesheet') return;
    var inline = 0;
    final selectedName = selected?.name;
    sheets
      ..clear()
      ..addAll([
        for (final resource in resources)
          if (!resource.flag('system'))
            StyleSheetInfo(
              resourceId: resource.str('resourceId'),
              href: resource.str('href'),
              documentHref: resource.str('nodeHref'),
              ruleCount: resource.integer('ruleCount'),
              isSystem: false,
              title: resource.str('title'),
              inlineOrdinal: resource.str('href').isEmpty ? inline++ : -1,
            ),
      ]);
    selected = null;
    for (final sheet in sheets) {
      if (sheet.name == selectedName) selected = sheet;
    }
    changed();
  }

  StyleSheetInfo? sheetById(String resourceId) {
    for (final sheet in sheets) {
      if (sheet.resourceId == resourceId) return sheet;
    }
    return null;
  }

  /// A line the editor is to put the caret on, and a count of such requests.
  (int, int)? revealLine;
  int _reveals = 0;

  void reveal(StyleSheetInfo sheet, int line) {
    if (line > 0) revealLine = (line, ++_reveals);
    select(sheet);
  }

  void select(StyleSheetInfo sheet) {
    selected = sheet;
    changed();
    load(sheet);
  }

  /// The script that sets `sheet` to the page's sheet that [info] stands for.
  static String locate(StyleSheetInfo info) {
    final own = 'node => node && node.hasAttribute && node.hasAttribute';
    if (info.isNew) {
      return 'const node = document.querySelector("style[data-fb-new=\\"${info.inlineOrdinal}\\"]");'
          'const sheet = node && node.sheet;';
    }
    return 'const owned = $own("data-fb-devtools");'
        'const authored = Array.from(document.styleSheets).filter(s => !owned(s.ownerNode));'
        '${info.href.isNotEmpty ? 'const sheet = authored.find(s => s.href === ${jsonEncode(info.href)});' : 'const sheet = authored.filter(s => !s.href)[${info.inlineOrdinal}];'}';
  }

  final Map<String, Future<void>> _loading = {};

  Future<void> load(StyleSheetInfo sheet) {
    if (sheet.text != null) return Future.value();
    // A block, not an arrow: returning the removed future from whenComplete
    // would make it wait for itself.
    return _loading[sheet.resourceId] ??= _load(sheet).whenComplete(() {
      _loading.remove(sheet.resourceId);
    });
  }

  Future<void> _load(StyleSheetInfo sheet) async {
    final actor = session.target?.styleSheetsActor;
    if (actor == null) return;
    String? text;
    try {
      final response = await session.connection.request(
        actor,
        'getText',
        {'resourceId': sheet.resourceId},
        // An engine without the fix never answers this after a navigation.
        const Duration(seconds: 3),
      );
      text = response.strOrNull('text');
    } on RdpError {
      // Read out of the page instead.
    }
    if (text == null) {
      try {
        final result = await session.runInPage(
          '${locate(sheet)}'
          'if (!sheet) throw new Error("The style sheet is gone");'
          'const node = sheet.ownerNode;'
          'if (node && node.tagName === "STYLE") return node.textContent;'
          'return Array.from(sheet.cssRules).map(rule => rule.cssText).join("\\n");',
        );
        text = '$result';
      } catch (failure) {
        sheet.error = 'This style sheet could not be read: $failure';
      }
    }
    if (text != null) {
      sheet
        ..text = text
        ..originalText = text;
      textRevision++;
    }
    changed();
  }

  /// Takes what is typed, and puts it in the page a moment later.
  void edit(StyleSheetInfo sheet, String text) {
    sheet.text = text;
    _applyTimer?.cancel();
    _applyTimer = Timer(const Duration(milliseconds: 350), () => apply(sheet));
    changed();
  }

  Future<void> apply(StyleSheetInfo sheet) async {
    final text = sheet.text;
    if (text == null) return;
    final css = jsonEncode(text);
    try {
      final count = await session.runInPage(
        '${locate(sheet)}'
        'const id = ${jsonEncode(sheet.resourceId)};'
        // A linked sheet cannot be rewritten, so a copy stands in for it.
        'let copy = document.querySelector("style[data-fb-copy=\\"" + id + "\\"]");'
        'if (copy) { copy.textContent = $css; return copy.sheet.cssRules.length; }'
        'if (!sheet) throw new Error("The style sheet is gone");'
        'const node = sheet.ownerNode;'
        'if (node && node.tagName === "STYLE") { node.textContent = $css; return node.sheet.cssRules.length; }'
        'copy = document.createElement("style");'
        'copy.setAttribute("data-fb-devtools", ""); copy.setAttribute("data-fb-copy", id);'
        'copy.textContent = $css; node.after(copy); sheet.disabled = true;'
        'return copy.sheet.cssRules.length;',
      );
      if (count is num) sheet.ruleCount = count.toInt();
      sheet.error = '';
      session.inspector.refreshStyles();
    } catch (failure) {
      sheet.error = '$failure';
    }
    changed();
  }

  Future<void> setDisabled(StyleSheetInfo sheet, bool disabled) async {
    try {
      await session.runInPage(
        '${locate(sheet)}'
        'const copy = document.querySelector("style[data-fb-copy=\\"" + ${jsonEncode(sheet.resourceId)} + "\\"]");'
        'const target = copy ? copy.sheet : sheet;'
        'if (!target) throw new Error("The style sheet is gone");'
        'target.disabled = $disabled; return true;',
      );
      sheet.disabled = disabled;
      session.inspector.refreshStyles();
    } catch (failure) {
      sheet.error = '$failure';
    }
    changed();
  }

  Future<void> createSheet([String text = '']) async {
    final ordinal = _newSheets++;
    try {
      await session.runInPage(
        'const node = document.createElement("style");'
        'node.setAttribute("data-fb-new", "$ordinal");'
        'node.textContent = ${jsonEncode(text)};'
        'document.head.appendChild(node); return true;',
      );
    } catch (_) {
      _newSheets--;
      return;
    }
    final sheet = StyleSheetInfo(
      resourceId: 'new-$ordinal',
      href: '',
      documentHref: session.url,
      ruleCount: 0,
      isSystem: false,
      title: '',
      inlineOrdinal: ordinal,
      isNew: true,
    )
      ..text = text
      ..originalText = text;
    sheets.add(sheet);
    selected = sheet;
    textRevision++;
    changed();
  }

  Future<void> save(StyleSheetInfo sheet) async {
    await load(sheet);
    final name = sheet.href.isEmpty ? 'style.css' : sheet.name;
    await session.onSaveFile?.call(name, utf8.encode(sheet.text ?? ''));
  }

  @override
  void dispose() {
    _applyTimer?.cancel();
    super.dispose();
  }
}
