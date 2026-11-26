import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/accessibility_controller.dart';
import '../model/session.dart';
import '../protocol/json.dart';
import '../ui/icons.dart';
import '../ui/json_tree.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The Accessibility Inspector: the page as assistive technology hears it.
class AccessibilityPanel extends StatefulWidget {
  const AccessibilityPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<AccessibilityPanel> createState() => _AccessibilityPanelState();
}

class _AccessibilityPanelState extends State<AccessibilityPanel> {
  final FocusNode _focus = FocusNode(debugLabel: 'accessibility tree');
  final ScrollController _scroll = ScrollController();
  String _category = '';

  AccessibilityController get accessibility => widget.session.accessibility;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) accessibility.activate();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final selected = accessibility.selected;
    if (selected == null) return KeyEventResult.ignored;
    final nodes = accessibility.visibleNodes;
    final index = nodes.indexOf(selected);
    void go(int to) {
      if (to < 0 || to >= nodes.length) return;
      accessibility.select(nodes[to]);
      if (!_scroll.hasClients) return;
      final top = to * 20.0;
      if (top < _scroll.offset) _scroll.jumpTo(top);
      if (top + 20 > _scroll.offset + _scroll.position.viewportDimension) {
        _scroll.jumpTo(top + 20 - _scroll.position.viewportDimension);
      }
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      go(index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      go(index - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (accessibility.expanded.contains(selected.actor)) {
        go(index + 1);
      } else if (selected.childCount > 0) {
        accessibility.expand(selected);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (accessibility.expanded.contains(selected.actor) && selected.childCount > 0) {
        accessibility.collapse(selected);
      } else if (selected.parent != null) {
        go(nodes.indexOf(selected.parent!));
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: accessibility,
    builder: (context, _) {
      final colors = context.dt;
      final issues = accessibility.issues;
      return ColoredBox(
        color: colors.body,
        child: Column(
          children: [
            DtToolbar(
              height: 27,
              children: [
                const SizedBox(width: 4),
                Text('Check for issues:', style: context.uiStyle()),
                const SizedBox(width: 2),
                DtDropdown(
                  label: accessibility.checking
                      ? 'Checking…'
                      : issues == null
                      ? 'None'
                      : _category.isEmpty
                      ? 'All Issues'
                      : _category,
                  entries: () => [
                    DtMenuItem('None', checked: issues == null, onSelected: accessibility.clearIssues),
                    for (final category in const ['', 'Contrast', 'Keyboard', 'Text Labels'])
                      DtMenuItem(
                        category.isEmpty ? 'All Issues' : category,
                        checked: issues != null && _category == category,
                        onSelected: () {
                          setState(() => _category = category);
                          accessibility.checkForIssues();
                        },
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Text('Simulate:', style: context.uiStyle(color: colors.textDim)),
                const SizedBox(width: 2),
                const DtDropdown(label: 'None', enabled: false, entries: _none, tooltip: 'The engine cannot simulate vision deficiencies'),
                const Spacer(),
                DtIconButton(DtGlyph.reload, iconSize: 12, tooltip: 'Refresh the accessibility tree', onPressed: accessibility.refresh),
              ],
            ),
            Expanded(child: issues != null ? _issues(context, issues) : _inspector(context)),
          ],
        ),
      );
    },
  );

  static List<DtMenuEntry> _none() => const [];

  Widget _issues(BuildContext context, List<AccessibilityIssue> all) {
    final colors = context.dt;
    final issues = all.where((i) => _category.isEmpty || i.category == _category).toList();
    if (issues.isEmpty) return const DtEmptyState('No issues found.');
    return ListView.builder(
      itemCount: issues.length,
      itemBuilder: (context, index) {
        final issue = issues[index];
        return DtHover(
          onTap: () {
            widget.session.selectTool('inspector');
            widget.session.inspector.selectPath(issue.path);
          },
          builder: (context, hovered) => Container(
            decoration: BoxDecoration(
              color: hovered ? colors.rowHover : null,
              border: Border(bottom: BorderSide(color: colors.splitter)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                DtIcon(DtGlyph.warning, size: 12, color: colors.warningIcon),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: Text(issue.category, style: context.uiStyle(color: colors.textDim, size: 11))),
                Expanded(child: Text(issue.message, style: context.uiStyle(color: colors.textStrong))),
                Text('Show in Inspector', style: context.uiStyle(color: colors.accent, size: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _inspector(BuildContext context) {
    final colors = context.dt;
    if (accessibility.root == null) {
      return DtEmptyState(
        accessibility.loading ? 'Loading the accessibility tree…' : accessibility.error.isEmpty ? 'No accessibility tree.' : accessibility.error,
        actions: [if (!accessibility.loading) DtButton('Retry', onPressed: accessibility.refresh)],
      );
    }
    final nodes = accessibility.visibleNodes;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(text, style: context.uiStyle(size: 11)),
    );
    return LayoutBuilder(
      builder: (context, constraints) => DtSplit(
        initialSize: (constraints.maxWidth * 0.38).clamp(220, 460),
        minSize: 180,
        minOther: 260,
        settings: widget.session.settings,
        settingKey: 'accessibility.sidebarWidth',
        first: Column(
          children: [
            Container(
              height: 22,
              decoration: BoxDecoration(color: colors.toolbar, border: Border(bottom: BorderSide(color: colors.splitter))),
              child: Row(children: [Expanded(child: header('Role')), Expanded(child: header('Name'))]),
            ),
            Expanded(
              child: Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: nodes.length,
                  itemExtent: 20,
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    final selected = accessibility.selected == node;
                    final open = accessibility.expanded.contains(node.actor);
                    return DtHover(
                      builder: (context, hovered) => Listener(
                        onPointerDown: (_) {
                          _focus.requestFocus();
                          accessibility.select(node);
                        },
                        child: Container(
                          color: selected ? colors.selection : hovered ? colors.rowHover : index.isOdd ? colors.rowAlternate : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 6.0 + node.depth * 14),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: node.childCount == 0 ? null : () => open ? accessibility.collapse(node) : accessibility.expand(node),
                                        child: SizedBox(
                                          width: 13,
                                          child: node.childCount == 0
                                              ? null
                                              : Center(child: DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim)),
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(node.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: selected ? colors.selectionText : colors.blue)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  node.name.isEmpty ? '' : '"${node.name}"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.monoStyle(color: selected ? colors.selectionText : colors.objectString),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        second: _properties(context),
      ),
    );
  }

  Widget _properties(BuildContext context) {
    final colors = context.dt;
    final node = accessibility.selected;
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 22,
            decoration: BoxDecoration(color: colors.toolbar, border: Border(bottom: BorderSide(color: colors.splitter))),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text('Properties', style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
          ),
          Expanded(
            child: node == null
                ? const DtEmptyState('Select an accessible object to see its properties.')
                : DtJsonTree(
                    key: ValueKey(node.actor),
                    value: {
                      'name': node.name,
                      'role': node.role,
                      'description': accessibility.properties.str('description'),
                      'value': accessibility.properties.str('value'),
                      'keyboardShortcut': accessibility.properties.str('keyboardShortcut'),
                      'childCount': node.childCount,
                      'indexInParent': accessibility.properties.integer('indexInParent'),
                      'states': accessibility.properties.list('states'),
                      'actions': accessibility.properties.list('actions'),
                      'attributes': accessibility.properties.obj('attributes'),
                      'relations': {for (final (type, target) in accessibility.relations) type: target},
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
