import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/session.dart';
import '../model/settings.dart';
import '../panels/accessibility_panel.dart';
import '../panels/console_panel.dart';
import '../panels/debugger_panel.dart';
import '../panels/inspector/inspector_panel.dart';
import '../panels/network_panel.dart';
import '../panels/other_panels.dart';
import '../panels/storage_panel.dart';
import '../panels/style_editor_panel.dart';
import '../ui/icons.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'settings_panel.dart';
import 'tools.dart';

/// What the toolbox needs to be told about where it is.
class ToolboxChrome {
  const ToolboxChrome({
    required this.onClose,
    required this.dock,
    required this.onDock,
    this.supportsWindow = false,
    this.responsive = false,
    this.onToggleResponsive,
  });

  final VoidCallback onClose;
  final DevToolsDock dock;
  final ValueChanged<DevToolsDock> onDock;
  final bool supportsWindow;
  final bool responsive;
  final VoidCallback? onToggleResponsive;
}

/// The developer tools for one tab: the row of tools, whichever is showing,
/// and the split console under it.
class DevToolsToolbox extends StatefulWidget {
  const DevToolsToolbox({
    super.key,
    required this.session,
    required this.panel,
    required this.onSelectPanel,
    required this.chrome,
    this.focusNode,
  });

  final ToolboxSession session;
  final String panel;
  final ValueChanged<String> onSelectPanel;
  final ToolboxChrome chrome;
  final FocusScopeNode? focusNode;

  @override
  State<DevToolsToolbox> createState() => _DevToolsToolboxState();
}

class _DevToolsToolboxState extends State<DevToolsToolbox> {
  /// The tools that have been opened, which keep their state while hidden.
  final Set<String> _built = {};
  FocusScopeNode? _ownScope;
  FocusScopeNode get _scope => widget.focusNode ?? (_ownScope ??= FocusScopeNode(debugLabel: 'devtools'));
  String _before = 'inspector';

  ToolboxSession get session => widget.session;

  @override
  void didUpdateWidget(DevToolsToolbox old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) _built.clear();
  }

  @override
  void dispose() {
    _ownScope?.dispose();
    super.dispose();
  }

  List<DevToolsTool> get _tools => [
    for (final tool in devToolsTools)
      if (session.settings.isPanelEnabled(tool.id) || tool.id == widget.panel) tool,
  ];

  void _select(String id) {
    if (widget.panel != 'settings') _before = widget.panel;
    widget.onSelectPanel(id);
  }

  void _toggleSettings() => _select(widget.panel == 'settings' ? _before : 'settings');

  void _toggleSplitConsole() => session.settings.splitConsole = !session.settings.splitConsole;

  void _step(int by) {
    final tools = _tools;
    final index = tools.indexWhere((t) => t.id == widget.panel);
    _select(tools[(index + by) % tools.length].id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    final key = event.logicalKey;
    final debugger = session.debugger;
    // In a window of its own the toolbox closes itself: the browser's own
    // shortcuts only hear its browser windows.
    final closes = widget.chrome.dock == DevToolsDock.window &&
        (key == LogicalKeyboardKey.f12 && !keyboard.isShiftPressed ||
            command && keyboard.isAltPressed && event.physicalKey == PhysicalKeyboardKey.keyI ||
            command && key == LogicalKeyboardKey.keyW);
    if (closes) {
      widget.chrome.onClose();
    } else if (key == LogicalKeyboardKey.f1) {
      _toggleSettings();
    } else if (key == LogicalKeyboardKey.escape) {
      if (session.inspector.picking) {
        session.inspector.stopPicker();
      } else if (widget.panel != 'console') {
        _toggleSplitConsole();
      } else {
        return KeyEventResult.ignored;
      }
    } else if (command && key == LogicalKeyboardKey.bracketRight) {
      _step(1);
    } else if (command && key == LogicalKeyboardKey.bracketLeft) {
      _step(-1);
    } else if (command && key == LogicalKeyboardKey.keyB && !keyboard.isShiftPressed && !keyboard.isAltPressed &&
        (widget.panel == 'console' || session.settings.splitConsole)) {
      session.console
        ..editorMode = !session.console.editorMode
        ..changed();
    } else if (key == LogicalKeyboardKey.f8) {
      debugger.isPaused ? debugger.resume() : debugger.interrupt();
    } else if (key == LogicalKeyboardKey.f10 && debugger.isPaused) {
      debugger.stepOver();
    } else if (key == LogicalKeyboardKey.f11 && debugger.isPaused) {
      keyboard.isShiftPressed ? debugger.stepOut() : debugger.stepIn();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    onKeyEvent: _onKey,
    child: Listener(
      onPointerDown: (_) {
        // Keys go to the tools once they have been clicked in.
        if (!_scope.hasFocus) _scope.requestFocus();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([session, session.settings]),
        builder: (context, _) {
          final colors = context.dt;
          return ColoredBox(
            color: colors.body,
            child: Column(
              children: [
                _tabBar(context),
                Expanded(child: _body(context)),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _body(BuildContext context) {
    switch (session.state) {
      case SessionState.connecting:
        return const DtEmptyState('Connecting to the page…');
      case SessionState.failed:
        return DtEmptyState(
          'The developer tools could not connect.',
          detail: session.failure,
          actions: [DtButton('Retry', primary: true, onPressed: session.start)],
        );
      case SessionState.closed:
        return const DtEmptyState('The connection to the engine closed.', detail: 'Close the developer tools and open them again.');
      case SessionState.ready:
        break;
    }
    final panel = widget.panel;
    _built.add(panel);
    final split = session.settings.splitConsole && panel != 'console' && panel != 'settings';
    final tools = Stack(
      fit: StackFit.expand,
      children: [
        for (final id in _built)
          Offstage(
            key: ValueKey(id),
            offstage: id != panel,
            child: TickerMode(
              enabled: id == panel,
              child: ExcludeFocus(excluding: id != panel, child: _panel(id)),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => DtSplit(
        axis: Axis.vertical,
        initialSize: (constraints.maxHeight * 0.35).clamp(120, 320),
        minSize: 70,
        minOther: 80,
        settings: session.settings,
        settingKey: 'splitConsoleHeight',
        showSecond: split,
        first: tools,
        second: split
            ? Column(
                children: [
                  DtToolbar(
                    height: 20,
                    topBorder: false,
                    children: [
                      const SizedBox(width: 4),
                      Text('Console', style: context.uiStyle(size: 11, color: context.dt.textDim)),
                      const Spacer(),
                      DtIconButton(DtGlyph.close, width: 18, height: 16, iconSize: 9, tooltip: 'Close split console (Esc)', onPressed: _toggleSplitConsole),
                    ],
                  ),
                  Expanded(child: ConsolePanel(key: const ValueKey('split-console'), session: session, autofocus: false)),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _panel(String id) => switch (id) {
    'inspector' => InspectorPanel(session: session),
    'console' => ConsolePanel(session: session),
    'debugger' => DebuggerPanel(session: session),
    'network' => NetworkPanel(session: session),
    'styleeditor' => StyleEditorPanel(session: session),
    'performance' => PerformancePanel(session: session),
    'memory' => const MemoryPanel(),
    'storage' => StoragePanel(session: session),
    'accessibility' => AccessibilityPanel(session: session),
    'application' => ApplicationPanel(session: session),
    _ => SettingsPanel(session: session),
  };

  // ------------------------------------------------------------ the tab bar

  static const double _barHeight = 29;

  Widget _tabBar(BuildContext context) {
    final colors = context.dt;
    final chrome = widget.chrome;
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(color: colors.tabToolbar, border: Border(bottom: BorderSide(color: colors.splitter))),
      child: Row(
        children: [
          const SizedBox(width: 3),
          ListenableBuilder(
            listenable: session.inspector,
            builder: (context, _) => DtIconButton(
              DtGlyph.picker,
              width: 28,
              height: 24,
              iconSize: 16,
              tooltip: 'Pick an element from the page (⇧⌘C)',
              active: session.inspector.picking,
              onPressed: session.isReady ? session.inspector.togglePicker : null,
            ),
          ),
          const DtToolbarSeparator(),
          Expanded(child: _tabs(context)),
          ..._buttons(context),
          const DtToolbarSeparator(),
          Builder(
            builder: (context) => DtIconButton(
              DtGlyph.meatball,
              width: 26,
              height: 24,
              tooltip: 'Customize Developer Tools and get help',
              onPressed: () => showDtMenuBelow(context, _mainMenu()),
            ),
          ),
          DtIconButton(DtGlyph.close, width: 26, height: 24, iconSize: 11, tooltip: 'Close Developer Tools', onPressed: chrome.onClose),
          const SizedBox(width: 3),
        ],
      ),
    );
  }

  List<Widget> _buttons(BuildContext context) => [
    ListenableBuilder(
      listenable: session.console,
      builder: (context, _) {
        final errors = session.console.errorCount;
        if (errors == 0) return const SizedBox.shrink();
        return DtTooltip(
          message: 'Show Split Console',
          child: DtHover(
            onTap: () => widget.panel == 'console' ? null : _toggleSplitConsole(),
            builder: (context, hovered) => Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: hovered ? context.dt.toolbarHover : null, borderRadius: BorderRadius.circular(2)),
              child: Row(
                children: [
                  const DtIcon(DtGlyph.error, size: 12, color: DtColors.errorFill),
                  const SizedBox(width: 4),
                  Text(errors > 99 ? '99+' : '$errors', style: context.uiStyle(color: context.dt.textStrong, size: 11)),
                ],
              ),
            ),
          ),
        );
      },
    ),
    if (widget.chrome.onToggleResponsive != null)
      DtIconButton(
        DtGlyph.responsive,
        width: 26,
        height: 24,
        tooltip: 'Responsive Design Mode (⌥⌘M)',
        active: widget.chrome.responsive,
        onPressed: widget.chrome.onToggleResponsive,
      ),
  ];

  static double _labelWidth(String label, TextStyle style) {
    final painter = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr)..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _tabs(BuildContext context) {
    final style = context.uiStyle();
    return LayoutBuilder(
      builder: (context, constraints) {
        final tools = _tools;
        // Icon, gap and padding around each label.
        final widths = [for (final tool in tools) (_labelWidth(tool.label, style) + 39).ceilToDouble()];
        var fit = tools.length;
        var used = widths.fold(0.0, (a, b) => a + b);
        if (widget.panel == 'settings') used += 90;
        if (used > constraints.maxWidth) {
          used = 26 + (widget.panel == 'settings' ? 90 : 0);
          fit = 0;
          while (fit < tools.length && used + widths[fit] <= constraints.maxWidth) {
            used += widths[fit];
            fit++;
          }
        }
        final shown = tools.take(fit).toList();
        final hidden = tools.skip(fit).toList();
        // The tool in use is always among those shown.
        final current = hidden.where((t) => t.id == widget.panel).firstOrNull;
        if (current != null) {
          hidden.remove(current);
          if (shown.isNotEmpty) hidden.insert(0, shown.removeLast());
          shown.add(current);
        }
        return ClipRect(
          child: Row(
            children: [
              // One tool alone in a very narrow toolbox may have to give way.
              for (final tool in shown)
                if (shown.length == 1) Flexible(child: _tab(context, tool)) else _tab(context, tool),
              if (widget.panel == 'settings') _tab(context, const DevToolsTool('settings', 'Settings', DtGlyph.gear)),
              if (hidden.isNotEmpty)
                Builder(
                  builder: (context) => DtIconButton(
                    DtGlyph.chevronDown,
                    width: 24,
                    height: 24,
                    iconSize: 12,
                    tooltip: 'Select another tool',
                    onPressed: () => showDtMenuBelow(context, [
                      for (final tool in hidden) DtMenuItem(tool.label, glyph: tool.glyph, shortcut: tool.shortcut, onSelected: () => _select(tool.id)),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tab(BuildContext context, DevToolsTool tool) {
    final colors = context.dt;
    final selected = widget.panel == tool.id;
    return ListenableBuilder(
      listenable: session.debugger,
      builder: (context, _) {
        final paused = tool.id == 'debugger' && session.debugger.isPaused;
        final foreground = selected || paused ? colors.accent : colors.text;
        return DtTooltip(
          message: tool.shortcut.isEmpty ? tool.label : '${tool.label} (${tool.shortcut})',
          child: DtHover(
            onTap: () => _select(tool.id),
            builder: (context, hovered) => Container(
              height: _barHeight - 1,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: selected ? colors.body : hovered ? colors.toolbarHover : null,
                border: Border(
                  top: BorderSide(
                    width: 2,
                    color: selected ? colors.accent : hovered ? colors.splitterStrong : const Color(0x00000000),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DtIcon(paused ? DtGlyph.pause : tool.glyph, size: 15, color: foreground),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(tool.label, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: context.uiStyle(color: foreground)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<DtMenuEntry> _mainMenu() {
    final chrome = widget.chrome;
    DtMenuItem dock(DevToolsDock value, String label, DtGlyph glyph) => DtMenuItem(
      label,
      glyph: chrome.dock == value ? null : glyph,
      checked: chrome.dock == value ? true : null,
      onSelected: () => chrome.onDock(value),
    );
    return [
      dock(DevToolsDock.left, 'Dock to Left', DtGlyph.dockLeft),
      dock(DevToolsDock.bottom, 'Dock to Bottom', DtGlyph.dockBottom),
      dock(DevToolsDock.right, 'Dock to Right', DtGlyph.dockRight),
      if (chrome.supportsWindow) dock(DevToolsDock.window, 'Separate Window', DtGlyph.dockWindow),
      const DtMenuItem.separator(),
      DtMenuItem(
        session.settings.splitConsole ? 'Hide Split Console' : 'Show Split Console',
        shortcut: 'Esc',
        enabled: widget.panel != 'console',
        onSelected: _toggleSplitConsole,
      ),
      if (chrome.onToggleResponsive != null)
        DtMenuItem('Responsive Design Mode', shortcut: '⌥⌘M', checked: chrome.responsive, onSelected: chrome.onToggleResponsive),
      const DtMenuItem.separator(),
      DtMenuItem('Force Reload', onSelected: () => session.reload(bypassCache: true)),
      DtMenuItem('Settings', shortcut: 'F1', onSelected: () => _select('settings')),
      const DtMenuItem.separator(),
      DtMenuItem('Documentation…', onSelected: () => session.onOpenLink?.call('https://firefox-source-docs.mozilla.org/devtools-user/')),
    ];
  }
}
