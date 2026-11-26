import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../model/session.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'markup_view.dart';
import 'rules_view.dart';
import 'sidebar_views.dart';

/// The Inspector: the page's markup beside what styles the selected element.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final FocusNode _markupFocus = FocusNode(debugLabel: 'markup');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'search HTML');
  String _query = '';

  ToolboxSession get session => widget.session;

  @override
  void dispose() {
    _markupFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _threePane => session.settings.flag('inspector.threePane');

  String get _tab => session.settings.text('inspector.sidebarTab', _threePane ? 'layout' : 'rules');

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
      if (event is KeyDownEvent && command && event.logicalKey == LogicalKeyboardKey.keyF) {
        _searchFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        // Narrow toolboxes, such as ones docked to a side, stack the panes.
        final narrow = constraints.maxWidth < 700;
        final markup = _markupPane(context);
        final sidebar = _sidebar(context, threePane: _threePane && !narrow);
        if (narrow) {
          return DtSplit(
            axis: Axis.vertical,
            initialSize: constraints.maxHeight * 0.5,
            settings: session.settings,
            settingKey: 'inspector.sidebarHeight',
            first: markup,
            second: sidebar,
          );
        }
        if (_threePane) {
          return DtSplit(
            initialSize: 320,
            minSize: 220,
            minOther: 380,
            settings: session.settings,
            settingKey: 'inspector.sidebarWidth',
            first: DtSplit(
              initialSize: 340,
              minSize: 200,
              minOther: 180,
              settings: session.settings,
              settingKey: 'inspector.rulesWidth',
              first: markup,
              second: RulesView(session: session),
            ),
            second: sidebar,
          );
        }
        return DtSplit(
          initialSize: (constraints.maxWidth * 0.42).clamp(300, 520),
          minSize: 240,
          minOther: 240,
          settings: session.settings,
          settingKey: 'inspector.sidebarWidth',
          first: markup,
          second: sidebar,
        );
      },
    ),
  );

  Widget _markupPane(BuildContext context) => ListenableBuilder(
    listenable: session.inspector,
    builder: (context, child) {
      final inspector = session.inspector;
      final search = inspector.search;
      final colors = context.dt;
      return Column(
        children: [
          DtToolbar(
            height: 25,
            children: [
              DtIconButton(
                DtGlyph.plus,
                iconSize: 12,
                tooltip: 'Create New Node',
                onPressed: inspector.selectedElement?.isElement ?? false
                    ? () => inspector.addChild(inspector.selectedElement!)
                    : null,
              ),
              const SizedBox(width: 3),
              Expanded(
                child: DtSearchBox(
                  value: _query,
                  glyph: DtGlyph.search,
                  focusNode: _searchFocus,
                  height: 19,
                  placeholder: 'Search HTML',
                  onChanged: (value) {
                    _query = value;
                    if (value.isEmpty) inspector.runSearch('');
                  },
                  onSubmitted: (value, backwards) => inspector.runSearch(value, backwards: backwards),
                  trailing: [
                    if (search != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          search.matches.isEmpty ? 'No matches' : '${search.index + 1} of ${search.matches.length}',
                          style: context.uiStyle(color: colors.textDim, size: 11),
                        ),
                      ),
                      DtIconButton(DtGlyph.chevronUp, width: 16, height: 16, iconSize: 10, onPressed: () => inspector.runSearch(search.query, backwards: true)),
                      DtIconButton(DtGlyph.chevronDown, width: 16, height: 16, iconSize: 10, onPressed: () => inspector.runSearch(search.query)),
                    ],
                    if (inspector.searching)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('Searching…', style: context.uiStyle(color: colors.textDim, size: 11)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              DtIconButton(
                DtGlyph.reload,
                iconSize: 12,
                tooltip: 'Reload the page',
                onPressed: session.reload,
              ),
            ],
          ),
          Expanded(child: child!),
          _Breadcrumbs(session: session),
        ],
      );
    },
    child: MarkupView(session: session, focusNode: _markupFocus),
  );

  Widget _sidebar(BuildContext context, {required bool threePane}) {
    final tabs = [
      if (!threePane) ('rules', 'Rules'),
      ('layout', 'Layout'),
      ('computed', 'Computed'),
      ('changes', 'Changes'),
      ('fonts', 'Fonts'),
    ];
    var selected = _tab;
    if (!tabs.any((t) => t.$1 == selected)) selected = tabs.first.$1;
    return Column(
      children: [
        DtSidebarTabs(
          tabs: tabs,
          selected: selected,
          onSelect: (id) => setState(() => session.settings.set('inspector.sidebarTab', id, quiet: true)),
          leading: DtIconButton(
            DtGlyph.paneToggle,
            tooltip: _threePane ? 'Toggle off the 3-pane inspector' : 'Toggle on the 3-pane inspector',
            active: _threePane,
            iconSize: 13,
            onPressed: () => setState(() => session.settings.set('inspector.threePane', !_threePane, quiet: true)),
          ),
        ),
        Expanded(
          child: switch (selected) {
            'layout' => LayoutView(session: session),
            'computed' => ComputedView(session: session),
            'changes' => ChangesView(session: session),
            'fonts' => FontsView(session: session),
            _ => RulesView(session: session),
          },
        ),
      ],
    );
  }
}

/// The chain of elements down to the selected one, along the bottom.
class _Breadcrumbs extends StatefulWidget {
  const _Breadcrumbs({required this.session});

  final ToolboxSession session;

  @override
  State<_Breadcrumbs> createState() => _BreadcrumbsState();
}

class _BreadcrumbsState extends State<_Breadcrumbs> {
  final ScrollController _scroll = ScrollController();
  String _shown = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session.inspector,
    builder: (context, _) {
      final colors = context.dt;
      final inspector = widget.session.inspector;
      final selected = inspector.selected;
      final path = selected?.path.where((n) => n.isElement || n == selected).toList() ?? const [];
      final key = path.map((n) => n.actor).join(' ');
      if (key != _shown) {
        _shown = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
      return Container(
        height: 22,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.toolbar,
          border: Border(top: BorderSide(color: colors.splitter)),
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, node) in path.indexed) ...[
                if (index > 0) DtIcon(DtGlyph.chevronRight, size: 9, color: colors.textDim),
                DtHover(
                  onTap: () => inspector.select(node, reveal: true),
                  onEnter: () => inspector.highlight(node),
                  onExit: inspector.unhighlight,
                  builder: (context, hovered) => Container(
                    height: 21,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    color: node == selected ? colors.selection : hovered ? colors.toolbarHover : null,
                    child: Text.rich(
                      TextSpan(
                        children: node.isElement
                            ? [
                                TextSpan(text: node.tag, style: TextStyle(color: node == selected ? colors.selectionText : colors.textStrong)),
                                if (node.id.isNotEmpty)
                                  TextSpan(text: '#${node.id}', style: TextStyle(color: node == selected ? colors.selectionText : colors.blue)),
                                if (node.classes.isNotEmpty)
                                  TextSpan(text: '.${node.classes.take(3).join('.')}', style: TextStyle(color: node == selected ? colors.selectionText : colors.textDim)),
                              ]
                            : [TextSpan(text: node.nodeName, style: TextStyle(color: node == selected ? colors.selectionText : colors.textDim))],
                      ),
                      style: context.monoStyle(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
