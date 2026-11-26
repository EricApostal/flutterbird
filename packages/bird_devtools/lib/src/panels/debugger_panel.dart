import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/console_controller.dart';
import '../model/debugger_controller.dart';
import '../model/object_tree.dart';
import '../model/remote_value.dart';
import '../model/session.dart';
import '../ui/code_view.dart';
import '../ui/icons.dart';
import '../ui/inline_editor.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/value_view.dart';
import '../ui/widgets.dart';
import '../util/pretty_print.dart';
import '../util/syntax.dart';

/// What a source looks like in the editor.
class _Document {
  _Document(this.lines, this.tokens, this.language, this.pretty);
  final List<String> lines;
  final List<List<Token>> tokens;
  final SyntaxLanguage language;

  /// Set when the lines shown are not the source's own.
  final PrettyPrinted? pretty;

  int shownLine(int line, [int column = 0]) => pretty?.formattedLineFor(line, column) ?? line;
}

/// The Debugger: sources, breakpoints, and what a paused page can tell.
class DebuggerPanel extends StatefulWidget {
  const DebuggerPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<DebuggerPanel> createState() => _DebuggerPanelState();
}

class _DebuggerPanelState extends State<DebuggerPanel> {
  final FocusNode _focus = FocusNode(debugLabel: 'debugger');
  final FocusNode _findFocus = FocusNode(debugLabel: 'find in source');
  final Map<String, _Document> _documents = {};
  final Map<String, String> _failures = {};
  final Set<String> _loading = {};
  String _leftTab = 'sources';
  final Set<String> _closedFolders = {};
  bool _finding = false;
  String _needle = '';
  int _findSerial = 0;
  CodeReveal? _findReveal;
  bool _quickOpen = false;
  (int, int) _cursor = (1, 0);

  /// The line a condition or log message is being typed for.
  ({int line, bool log})? _condition;

  String _projectQuery = '';
  List<(SourceInfo, int, String)> _projectMatches = const [];
  bool _projectSearching = false;

  OverlayEntry? _preview;
  Timer? _previewTimer;
  int _previewGeneration = 0;
  bool _overPreview = false;

  ToolboxSession get session => widget.session;
  DebuggerController get debugger => session.debugger;

  @override
  void dispose() {
    _hidePreview(force: true);
    _focus.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  _Document? _document(String url) {
    final source = debugger.sourceForUrl(url);
    if (source == null) return null;
    final pretty = debugger.prettyPrinted.contains(url);
    final key = '${source.actor}|$pretty';
    final held = _documents[key];
    if (held != null) return held;
    if (_failures.containsKey(key) || !_loading.add(key)) return null;
    debugger.loadSource(source).then(
      (text) {
        final language = languageFor(text.contentType, url);
        final formatted = !pretty
            ? null
            : language == SyntaxLanguage.css
            ? prettyPrintCss(text.text)
            : prettyPrintJavaScript(text.text);
        final lines = formatted?.lines ?? text.text.split('\n');
        _documents[key] = _Document(lines, highlightLines(lines, language), language, formatted);
        _loading.remove(key);
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        _failures[key] = '$error';
        _loading.remove(key);
        if (mounted) setState(() {});
      },
    );
    return null;
  }

  // ------------------------------------------------------------ keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    final key = event.logicalKey;
    if (command && key == LogicalKeyboardKey.keyP && !keyboard.isShiftPressed) {
      setState(() => _quickOpen = true);
    } else if (command && keyboard.isShiftPressed && key == LogicalKeyboardKey.keyF) {
      setState(() => _leftTab = 'search');
    } else if (command && key == LogicalKeyboardKey.keyF) {
      setState(() => _finding = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _findFocus.requestFocus());
    } else if (key == LogicalKeyboardKey.escape && (_finding || _quickOpen || _condition != null)) {
      setState(() {
        _finding = false;
        _quickOpen = false;
        _condition = null;
        _needle = '';
      });
      _focus.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _onKey,
    child: Listener(
      onPointerDown: (_) {
        if (!_focus.hasFocus) _focus.requestFocus();
      },
      child: ListenableBuilder(
        listenable: debugger,
        builder: (context, _) => ColoredBox(
          color: context.dt.body,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 700;
              final center = _center(context);
              final right = _rightPane(context);
              if (narrow) {
                return DtSplit(
                  axis: Axis.vertical,
                  initialSize: constraints.maxHeight * 0.45,
                  settings: session.settings,
                  settingKey: 'debugger.stackedHeight',
                  first: center,
                  second: right,
                );
              }
              return DtSplit(
                sizeSecond: false,
                initialSize: 220,
                minSize: 140,
                minOther: 460,
                settings: session.settings,
                settingKey: 'debugger.leftWidth',
                first: _leftPane(context),
                second: DtSplit(
                  initialSize: 290,
                  minSize: 200,
                  minOther: 240,
                  settings: session.settings,
                  settingKey: 'debugger.rightWidth',
                  first: center,
                  second: right,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  // ------------------------------------------------------------ left pane

  Widget _leftPane(BuildContext context) => Column(
    children: [
      DtSidebarTabs(
        tabs: const [('sources', 'Sources'), ('outline', 'Outline'), ('search', 'Search')],
        selected: _leftTab,
        onSelect: (tab) => setState(() => _leftTab = tab),
      ),
      Expanded(
        child: switch (_leftTab) {
          'outline' => _outline(context),
          'search' => _search(context),
          _ => _sourceTree(context),
        },
      ),
    ],
  );

  Widget _sourceTree(BuildContext context) {
    final sources = debugger.sources;
    if (sources.isEmpty) return const DtEmptyState('This page has no sources.');
    // Host, then folders, then files.
    final rows = <Widget>[];
    final hosts = <String, List<SourceInfo>>{};
    for (final source in sources) {
      hosts.putIfAbsent(source.host, () => []).add(source);
    }
    for (final host in hosts.entries) {
      final hostOpen = !_closedFolders.contains(host.key);
      rows.add(_treeRow(context, 0, host.key, DtGlyph.domain, open: hostOpen, onTap: () => _toggleFolder(host.key)));
      if (!hostOpen) continue;
      final seen = <String>{};
      final files = host.value.toList()
        ..sort((a, b) {
          final pa = Uri.tryParse(a.url)?.pathSegments ?? const [];
          final pb = Uri.tryParse(b.url)?.pathSegments ?? const [];
          for (var i = 0; i < pa.length && i < pb.length; i++) {
            final aIsFolder = i < pa.length - 1;
            final bIsFolder = i < pb.length - 1;
            if (aIsFolder != bIsFolder) return aIsFolder ? -1 : 1;
            final order = pa[i].compareTo(pb[i]);
            if (order != 0) return order;
          }
          return pa.length.compareTo(pb.length);
        });
      for (final source in files) {
        final segments = Uri.tryParse(source.url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const <String>[];
        var depth = 1;
        var path = host.key;
        var hidden = false;
        for (var i = 0; i + 1 < segments.length; i++) {
          path = '$path/${segments[i]}';
          final open = !_closedFolders.contains(path);
          if (!hidden && seen.add(path)) {
            final folder = path;
            rows.add(_treeRow(context, depth, segments[i], DtGlyph.folder, open: open, onTap: () => _toggleFolder(folder)));
          }
          if (!open) hidden = true;
          depth++;
        }
        if (hidden) continue;
        rows.add(
          _treeRow(
            context,
            depth,
            source.fileName,
            source.fileName.endsWith('.js') || source.fileName.endsWith('.mjs') ? DtGlyph.script : DtGlyph.file,
            selected: debugger.selectedUrl == source.url,
            dim: source.isBlackBoxed,
            tooltip: source.url,
            onTap: () => debugger.openSource(source.url),
            onMenu: (position) => showDtMenu(context, position, [
              DtMenuItem('Copy Source URI', onSelected: () => Clipboard.setData(ClipboardData(text: source.url))),
              DtMenuItem(
                source.isBlackBoxed ? 'Unignore Source' : 'Ignore Source',
                onSelected: () => debugger.setBlackBoxed(source, !source.isBlackBoxed),
              ),
            ]),
          ),
        );
      }
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 2), children: rows);
  }

  void _toggleFolder(String path) =>
      setState(() => _closedFolders.contains(path) ? _closedFolders.remove(path) : _closedFolders.add(path));

  Widget _treeRow(
    BuildContext context,
    int depth,
    String label,
    DtGlyph glyph, {
    bool? open,
    bool selected = false,
    bool dim = false,
    String tooltip = '',
    required VoidCallback onTap,
    ValueChanged<Offset>? onMenu,
  }) {
    final colors = context.dt;
    final foreground = selected ? colors.selectionText : dim ? colors.textDim : colors.text;
    return DtHover(
      onTap: onTap,
      onSecondaryTapDown: onMenu == null ? null : (d) => onMenu(d.globalPosition),
      builder: (context, hovered) => Container(
        height: 20,
        color: selected ? colors.selection : hovered ? colors.rowHover : null,
        padding: EdgeInsets.only(left: 6 + depth * 13, right: 6),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              child: open == null ? null : DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: colors.textDim),
            ),
            DtIcon(glyph, size: 13, color: selected ? colors.selectionText : colors.textDim),
            const SizedBox(width: 5),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }

  static final RegExp _functionPattern = RegExp(
    r'(?:^|[^\w$.])(?:async\s+)?function\s*\*?\s*([\w$]+)\s*\(([^)]*)\)|class\s+([\w$]+)|(?:const|let|var)\s+([\w$]+)\s*=\s*(?:async\s*)?(?:\(([^)]*)\)|([\w$]+))\s*=>|^\s*(?:static\s+|async\s+|get\s+|set\s+)*([\w$]+)\s*\(([^)]*)\)\s*\{',
  );

  Widget _outline(BuildContext context) {
    final url = debugger.selectedUrl;
    final document = url == null ? null : _document(url);
    if (document == null) return const DtEmptyState('Open a file to see its outline.');
    final entries = <(String, int)>[];
    for (final (index, line) in document.lines.indexed) {
      if (line.length > 2000) continue;
      final match = _functionPattern.firstMatch(line);
      if (match == null) continue;
      final String label;
      if (match.group(1) != null) {
        label = '${match.group(1)}(${match.group(2)})';
      } else if (match.group(3) != null) {
        label = 'class ${match.group(3)}';
      } else if (match.group(4) != null) {
        label = '${match.group(4)}(${match.group(5) ?? match.group(6) ?? ''})';
      } else {
        final name = match.group(7)!;
        if (const {'if', 'for', 'while', 'switch', 'catch', 'function'}.contains(name)) continue;
        label = '$name(${match.group(8)})';
      }
      entries.add((label, index + 1));
    }
    if (entries.isEmpty) return const DtEmptyState('No functions');
    return ListView(
      children: [
        for (final (label, line) in entries)
          DtHover(
            onTap: () => setState(() => _findReveal = CodeReveal(line, 1000000 + ++_findSerial)),
            builder: (context, hovered) => Container(
              height: 19,
              color: hovered ? context.dt.rowHover : null,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: context.dt.blue)),
            ),
          ),
      ],
    );
  }

  Future<void> _searchProject(String query) async {
    setState(() {
      _projectSearching = true;
      _projectQuery = query;
    });
    final matches = <(SourceInfo, int, String)>[];
    final needle = query.toLowerCase();
    if (needle.isNotEmpty) {
      for (final source in debugger.sources) {
        try {
          final text = await debugger.loadSource(source);
          for (final (index, line) in text.text.split('\n').indexed) {
            if (line.toLowerCase().contains(needle)) matches.add((source, index + 1, line.trim()));
            if (matches.length >= 500) break;
          }
        } catch (_) {
          // Sources that cannot be read are not searched.
        }
        if (matches.length >= 500) break;
      }
    }
    if (!mounted || query != _projectQuery) return;
    setState(() {
      _projectMatches = matches;
      _projectSearching = false;
    });
  }

  Widget _search(BuildContext context) {
    final colors = context.dt;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: DtSearchBox(
            value: _projectQuery,
            glyph: DtGlyph.search,
            placeholder: 'Find in files…',
            onChanged: (value) => _projectQuery = value,
            onSubmitted: (value, _) => _searchProject(value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _projectSearching ? 'Searching…' : '${_projectMatches.length} results',
              style: context.uiStyle(color: colors.textDim, size: 11),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _projectMatches.length,
            itemBuilder: (context, index) {
              final (source, line, text) = _projectMatches[index];
              return DtHover(
                onTap: () => debugger.openSource(source.url, line: line),
                builder: (context, hovered) => Container(
                  color: hovered ? colors.rowHover : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${source.fileName}:$line', style: context.uiStyle(color: colors.textDim, size: 10)),
                      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: colors.textStrong)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ center

  Widget _center(BuildContext context) {
    final url = debugger.selectedUrl;
    final document = url == null ? null : _document(url);
    return Column(
      children: [
        _sourceTabs(context),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _editor(context, url, document)),
              if (_quickOpen)
                Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: _QuickOpen(
                    sources: debugger.sources,
                    onClose: () {
                      setState(() => _quickOpen = false);
                      _focus.requestFocus();
                    },
                    onOpen: (source, line) {
                      setState(() => _quickOpen = false);
                      debugger.openSource(source.url, line: line);
                      _focus.requestFocus();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_condition != null && url != null) _conditionBar(context, url, document),
        if (_finding) _findBar(context, document),
        if (url != null) _statusBar(context, url, document),
      ],
    );
  }

  Widget _sourceTabs(BuildContext context) {
    final colors = context.dt;
    return Container(
      height: 25,
      decoration: BoxDecoration(color: colors.toolbar, border: Border(bottom: BorderSide(color: colors.splitter))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in debugger.openUrls)
            DtTooltip(
              message: url,
              child: DtHover(
                onTap: () => debugger.openSource(url),
                builder: (context, hovered) {
                  final selected = url == debugger.selectedUrl;
                  final name = debugger.sourceForUrl(url)?.fileName ?? SourceLocation(url).fileName;
                  return Container(
                    padding: const EdgeInsets.only(left: 9, right: 3),
                    decoration: BoxDecoration(
                      color: selected ? colors.body : hovered ? colors.toolbarHover : null,
                      border: Border(
                        top: BorderSide(width: 2, color: selected ? colors.accent : const Color(0x00000000)),
                        right: BorderSide(color: colors.splitter),
                      ),
                    ),
                    child: Row(
                      children: [
                        DtIcon(DtGlyph.script, size: 12, color: colors.textDim),
                        const SizedBox(width: 5),
                        Text(name, style: context.uiStyle(color: selected ? colors.textStrong : colors.text)),
                        const SizedBox(width: 4),
                        DtIconButton(DtGlyph.close, width: 16, height: 16, iconSize: 9, tooltip: 'Close tab', onPressed: () => debugger.closeSource(url)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context, String? url, _Document? document) {
    final colors = context.dt;
    if (url == null) {
      return const DtEmptyState('⌘P Go to file', detail: '⌘⇧F Find in files · ⌘F Find in the open file');
    }
    if (document == null) {
      final source = debugger.sourceForUrl(url);
      final failure = _failures['${source?.actor}|${debugger.prettyPrinted.contains(url)}'];
      return DtEmptyState(source == null ? 'This source is not in the page any more.' : failure ?? 'Loading…');
    }
    final marks = <int, GutterMark>{};
    for (final breakpoint in debugger.breakpoints) {
      if (breakpoint.url != url) continue;
      final line = document.shownLine(breakpoint.line, breakpoint.column ?? 0);
      final color = breakpoint.isLogPoint
          ? colors.purple
          : breakpoint.isConditional
          ? colors.orange
          : colors.breakpoint;
      marks[line] = GutterMark(color, hollow: breakpoint.disabled || !debugger.breakpointsActive);
    }
    final pause = debugger.pause;
    final frame = debugger.selectedFrame;
    int? pausedLine;
    if (pause != null && frame != null && debugger.sourceForActor(frame.sourceActor)?.url == url) {
      pausedLine = document.shownLine(frame.line, frame.column);
    }
    var reveal = _findReveal;
    final request = debugger.reveal;
    if (request != null && request.url == url && (reveal == null || request.serial > _lastRevealSerial)) {
      _lastRevealSerial = request.serial;
      _findReveal = null;
      reveal = CodeReveal(document.shownLine(request.line, request.column), request.serial);
    }
    final breakable = debugger.breakableLines[url];
    return DtCodeView(
      key: ValueKey('$url ${document.pretty != null}'),
      lines: document.lines,
      tokens: document.tokens,
      gutterMarks: marks,
      highlightedLine: pausedLine,
      highlightedColumn: document.pretty == null ? frame?.column : null,
      needle: _finding ? _needle : '',
      reveal: reveal,
      dimmedLines: breakable == null || document.pretty != null || breakable.isEmpty ? null : (line) => !breakable.contains(line),
      onGutterTap: (line) => _toggleAt(url, document, line),
      onGutterMenu: (line, position) => showDtMenu(context, position, _lineMenu(url, document, line, '')),
      onLineMenu: (line, position, selected) => showDtMenu(context, position, _lineMenu(url, document, line, selected)),
      onCursorLine: (line, column) => setState(() => _cursor = (line, column)),
      onHoverWord: debugger.isPaused ? _showPreview : null,
      onHoverEnd: _schedulePreviewHide,
    );
  }

  int _lastRevealSerial = 0;

  /// Where in the source a shown line is.
  (int, int?) _original(_Document document, int shown) {
    final pretty = document.pretty;
    if (pretty == null) return (shown, null);
    final (line, column) = pretty.originalFor(shown);
    return (line, column);
  }

  void _toggleAt(String url, _Document document, int shown) {
    final (line, column) = _original(document, shown);
    debugger.toggleBreakpoint(url, line, column: column);
  }

  List<DtMenuEntry> _lineMenu(String url, _Document document, int shown, String selected) {
    final (line, column) = _original(document, shown);
    final existing = debugger.breakpointAt(url, line, column);
    final source = debugger.sourceForUrl(url);
    return [
      DtMenuItem(existing == null ? 'Add Breakpoint' : 'Remove Breakpoint', onSelected: () => _toggleAt(url, document, shown)),
      DtMenuItem(
        existing?.isConditional ?? false ? 'Edit Condition' : 'Add Condition',
        onSelected: () => setState(() => _condition = (line: shown, log: false)),
      ),
      DtMenuItem(
        existing?.isLogPoint ?? false ? 'Edit Logpoint' : 'Add Logpoint',
        onSelected: () => setState(() => _condition = (line: shown, log: true)),
      ),
      if (existing != null)
        DtMenuItem(
          existing.disabled ? 'Enable Breakpoint' : 'Disable Breakpoint',
          onSelected: () => debugger.setBreakpointDisabled(existing, !existing.disabled),
        ),
      DtMenuItem('Continue to Here', enabled: debugger.isPaused, onSelected: () => debugger.continueTo(url, line, column: column)),
      const DtMenuItem.separator(),
      DtMenuItem('Copy', enabled: selected.isNotEmpty, shortcut: '⌘C', onSelected: () => Clipboard.setData(ClipboardData(text: selected))),
      DtMenuItem('Add Watch Expression', enabled: selected.isNotEmpty, onSelected: () => debugger.addWatch(selected)),
      DtMenuItem(
        'Evaluate in Console',
        enabled: selected.isNotEmpty,
        onSelected: () {
          session.selectTool('console');
          session.console.execute(selected);
        },
      ),
      const DtMenuItem.separator(),
      if (source != null)
        DtMenuItem(
          source.isBlackBoxed ? 'Unignore Source' : 'Ignore Source',
          onSelected: () => debugger.setBlackBoxed(source, !source.isBlackBoxed),
        ),
      DtMenuItem('Copy Source URI', onSelected: () => Clipboard.setData(ClipboardData(text: url))),
    ];
  }

  Widget _conditionBar(BuildContext context, String url, _Document? document) {
    final colors = context.dt;
    final condition = _condition!;
    if (document == null) return const SizedBox.shrink();
    final (line, column) = _original(document, condition.line);
    final existing = debugger.breakpointAt(url, line, column);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: colors.toolbar, border: Border(top: BorderSide(color: condition.log ? colors.purple : colors.orange, width: 2))),
      child: Row(
        children: [
          Text('${condition.log ? 'Log message' : 'Condition'} for line $line  ', style: context.uiStyle(color: colors.textStrong)),
          Expanded(
            child: DtInlineEditor(
              key: ValueKey('${condition.line} ${condition.log}'),
              initial: condition.log ? existing?.logValue ?? '' : existing?.condition ?? '',
              placeholder: condition.log ? "'Message', value" : 'Expression that must be true to pause',
              maxWidth: 2000,
              minWidth: 2000,
              onCancel: () => setState(() => _condition = null),
              onCommit: (value, end) {
                setState(() => _condition = null);
                if (end == EditEnd.blur) return;
                debugger.addBreakpoint(
                  url,
                  line,
                  column: column,
                  condition: condition.log ? existing?.condition ?? '' : value.trim(),
                  logValue: condition.log ? value.trim() : existing?.logValue ?? '',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _findBar(BuildContext context, _Document? document) {
    final colors = context.dt;
    final matches = <int>[];
    if (_needle.isNotEmpty && document != null) {
      final needle = _needle.toLowerCase();
      for (final (index, line) in document.lines.indexed) {
        if (line.toLowerCase().contains(needle)) matches.add(index + 1);
      }
    }
    void jump(bool backwards) {
      if (matches.isEmpty) return;
      final current = _findReveal?.line ?? 0;
      final next = backwards
          ? matches.lastWhere((line) => line < current, orElse: () => matches.last)
          : matches.firstWhere((line) => line > current, orElse: () => matches.first);
      setState(() => _findReveal = CodeReveal(next, 1000000 + ++_findSerial));
    }

    return DtToolbar(
      topBorder: true,
      bottomBorder: false,
      height: 28,
      children: [
        Expanded(
          child: DtSearchBox(
            value: _needle,
            glyph: DtGlyph.search,
            focusNode: _findFocus,
            placeholder: 'Search in file…',
            onChanged: (value) => setState(() => _needle = value),
            onSubmitted: (_, backwards) => jump(backwards),
            trailing: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(_needle.isEmpty ? '' : '${matches.length} matching lines', style: context.uiStyle(color: colors.textDim, size: 11)),
              ),
              DtIconButton(DtGlyph.chevronUp, width: 16, height: 16, iconSize: 10, onPressed: () => jump(true)),
              DtIconButton(DtGlyph.chevronDown, width: 16, height: 16, iconSize: 10, onPressed: () => jump(false)),
            ],
          ),
        ),
        DtIconButton(DtGlyph.close, iconSize: 10, onPressed: () => setState(() {
          _finding = false;
          _needle = '';
        })),
      ],
    );
  }

  Widget _statusBar(BuildContext context, String url, _Document? document) {
    final colors = context.dt;
    final source = debugger.sourceForUrl(url);
    return DtToolbar(
      height: 23,
      topBorder: true,
      bottomBorder: false,
      children: [
        DtIconButton(
          DtGlyph.prettyPrint,
          width: 24,
          height: 19,
          iconSize: 15,
          tooltip: 'Pretty print source',
          active: debugger.prettyPrinted.contains(url),
          onPressed: () => debugger.togglePrettyPrint(url),
        ),
        if (source != null)
          DtIconButton(
            DtGlyph.blackbox,
            width: 22,
            height: 19,
            iconSize: 12,
            tooltip: source.isBlackBoxed ? 'Unignore source' : 'Ignore source',
            active: source.isBlackBoxed,
            onPressed: () => debugger.setBlackBoxed(source, !source.isBlackBoxed),
          ),
        if (document != null && document.pretty == null && looksMinified(document.lines.join('\n')))
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: DtHover(
              cursor: SystemMouseCursors.click,
              onTap: () => debugger.togglePrettyPrint(url),
              builder: (context, hovered) => Text('This file looks minified — pretty print it', style: context.uiStyle(color: colors.accent, size: 11)),
            ),
          ),
        const Spacer(),
        Text('(Line ${_cursor.$1}, column ${_cursor.$2 + 1})  ', style: context.uiStyle(color: colors.textDim, size: 11)),
      ],
    );
  }

  // ------------------------------------------------------------ hover previews

  void _showPreview(String expression, Offset position) {
    _previewTimer?.cancel();
    final generation = ++_previewGeneration;
    _previewTimer = Timer(const Duration(milliseconds: 350), () async {
      final frame = debugger.selectedFrame?.actor;
      if (frame == null) return;
      final EvaluationOutcome outcome;
      try {
        outcome = await session.evaluate(expression, frameActor: frame, timeout: const Duration(seconds: 3));
      } catch (_) {
        return;
      }
      if (!mounted || generation != _previewGeneration || outcome.threw) return;
      if (outcome.value.kind == RemoteKind.undefined) return;
      _hidePreview(force: true);
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      final colors = context.dt;
      final box = overlay.context.findRenderObject()! as RenderBox;
      final at = box.globalToLocal(position);
      final entry = OverlayEntry(
        builder: (context) => DtTheme(
          colors: colors,
          child: Positioned(
            left: at.dx.clamp(4, box.size.width - 340),
            top: at.dy + 10 > box.size.height - 200 ? at.dy - 210 : at.dy + 10,
            child: MouseRegion(
              onEnter: (_) => _overPreview = true,
              onExit: (_) {
                _overPreview = false;
                _schedulePreviewHide();
              },
              child: Container(
                width: 330,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.popup,
                  border: Border.all(color: colors.popupBorder),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: SingleChildScrollView(
                  child: Builder(
                    builder: (context) => ValueTreeView(
                      session: session,
                      tree: debugger.objects,
                      path: 'preview:$generation',
                      entry: ObjectEntry(expression, value: outcome.value),
                      label: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      _preview = entry;
      overlay.insert(entry);
    });
  }

  void _schedulePreviewHide() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_overPreview) _hidePreview(force: true);
    });
  }

  void _hidePreview({bool force = false}) {
    if (force) _previewTimer?.cancel();
    _preview?.remove();
    _preview?.dispose();
    _preview = null;
    _overPreview = false;
  }

  // ------------------------------------------------------------ right pane

  bool _open(String section) => !session.settings.flag('debugger.closed.$section');

  void _toggleSection(String section) {
    session.settings.set('debugger.closed.$section', _open(section), quiet: true);
    setState(() {});
  }

  Widget _section(String id, String title, Widget child, {List<Widget> actions = const []}) => DtAccordion(
    title: title,
    expanded: _open(id),
    onToggle: () => _toggleSection(id),
    actions: actions,
    child: child,
  );

  Widget _rightPane(BuildContext context) {
    final colors = context.dt;
    final pause = debugger.pause;
    if (pause == null) _hidePreviewLater();
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        children: [
          DtToolbar(
            height: 25,
            children: [
              pause != null
                  ? DtIconButton(DtGlyph.play, tooltip: 'Resume (F8)', onPressed: debugger.resume, color: colors.accent)
                  : DtIconButton(DtGlyph.pause, tooltip: 'Pause on the next script (F8)', active: debugger.pauseRequested, onPressed: debugger.interrupt),
              DtIconButton(DtGlyph.stepOver, tooltip: 'Step over (F10)', onPressed: pause == null ? null : debugger.stepOver),
              DtIconButton(DtGlyph.stepIn, tooltip: 'Step in (F11)', onPressed: pause == null ? null : debugger.stepIn),
              DtIconButton(DtGlyph.stepOut, tooltip: 'Step out (⇧F11)', onPressed: pause == null ? null : debugger.stepOut),
              const Spacer(),
              DtIconButton(
                DtGlyph.deactivate,
                tooltip: debugger.breakpointsActive ? 'Deactivate breakpoints' : 'Activate breakpoints',
                active: !debugger.breakpointsActive,
                onPressed: () => debugger.setOption('breakpointsActive', !debugger.breakpointsActive),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                if (pause != null) _pausedBanner(context, pause),
                if (debugger.error.isNotEmpty)
                  Container(
                    color: colors.errorBackground,
                    padding: const EdgeInsets.all(6),
                    child: Text(debugger.error, style: context.uiStyle(color: colors.errorText, size: 11)),
                  ),
                _section(
                  'watch',
                  'Watch expressions',
                  _watches(context),
                  actions: [
                    DtIconButton(DtGlyph.reload, width: 18, height: 18, iconSize: 10, tooltip: 'Refresh watch expressions', onPressed: debugger.refreshWatches),
                    DtIconButton(DtGlyph.trash, width: 18, height: 18, iconSize: 11, tooltip: 'Remove all watch expressions', onPressed: debugger.watches.isEmpty ? null : debugger.removeAllWatches),
                  ],
                ),
                _section('breakpoints', 'Breakpoints', _breakpoints(context)),
                if (pause != null) _section('stack', 'Call stack', _callStack(context, pause)),
                if (pause != null) _section('scopes', 'Scopes', _scopes(context, pause)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _hidePreviewLater() {
    if (_preview == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _hidePreview(force: true));
  }

  Widget _pausedBanner(BuildContext context, PauseState pause) {
    final colors = context.dt;
    final exception = pause.exception;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.paused,
        border: Border(bottom: BorderSide(color: colors.pausedBorder)),
      ),
      child: Row(
        children: [
          DtIcon(DtGlyph.info, size: 13, color: colors.isDark ? colors.yellow : colors.warningText),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pause.headline, style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w500)),
                if (exception != null)
                  Text(exception.describe(), maxLines: 3, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: colors.errorText))
                else if (pause.message.isNotEmpty)
                  Text(pause.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: colors.textStrong)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int? _editingWatch;

  Widget _watches(BuildContext context) {
    final colors = context.dt;
    final watches = debugger.watches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, expression) in watches.indexed)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _editingWatch == index
                      ? DtInlineEditor(
                          initial: expression,
                          maxWidth: 600,
                          onCancel: () => setState(() => _editingWatch = null),
                          onCommit: (value, end) {
                            setState(() => _editingWatch = null);
                            debugger.setWatch(index, value);
                          },
                        )
                      : GestureDetector(
                          onDoubleTap: () => setState(() => _editingWatch = index),
                          child: index < debugger.watchValues.length && debugger.watchValues[index] != null
                              ? ValueTreeView(
                                  session: session,
                                  tree: debugger.objects,
                                  path: 'watch:$index',
                                  entry: ObjectEntry(expression, value: debugger.watchValues[index]!.value),
                                  label: true,
                                )
                              : Text('$expression: …', style: context.monoStyle(color: colors.textDim)),
                        ),
                ),
                DtIconButton(DtGlyph.close, width: 16, height: 16, iconSize: 9, tooltip: 'Remove', onPressed: () => debugger.setWatch(index, '')),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
          child: _NewWatchField(onAdd: debugger.addWatch),
        ),
      ],
    );
  }

  Widget _breakpoints(BuildContext context) {
    final colors = context.dt;
    Widget option(String label, String name, bool value, {double indent = 0}) => Padding(
      padding: EdgeInsets.fromLTRB(10 + indent, 3, 8, 3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DtCheckbox(label: label, value: value, onChanged: (on) => debugger.setOption(name, on)),
      ),
    );
    final files = <String, List<Breakpoint>>{};
    for (final breakpoint in debugger.breakpoints) {
      files.putIfAbsent(breakpoint.url, () => []).add(breakpoint);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        option('Pause on debugger statement', 'pauseOnDebuggerStatement', debugger.pauseOnDebuggerStatement),
        option('Pause on exceptions', 'pauseOnExceptions', debugger.pauseOnExceptions),
        if (debugger.pauseOnExceptions) option('Pause on caught exceptions', 'pauseOnCaughtExceptions', debugger.pauseOnCaughtExceptions, indent: 16),
        for (final file in files.entries) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 8, 2),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.splitter))),
            child: Row(
              children: [
                DtIcon(DtGlyph.script, size: 12, color: colors.textDim),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(SourceLocation(file.key).fileName, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: colors.textStrong)),
                ),
              ],
            ),
          ),
          for (final breakpoint in file.value)
            DtHover(
              onTap: () => debugger.openSource(breakpoint.url, line: breakpoint.line, column: breakpoint.column ?? 0),
              onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, [
                DtMenuItem(breakpoint.disabled ? 'Enable Breakpoint' : 'Disable Breakpoint', onSelected: () => debugger.setBreakpointDisabled(breakpoint, !breakpoint.disabled)),
                DtMenuItem('Remove Breakpoint', onSelected: () => debugger.removeBreakpoint(breakpoint)),
                DtMenuItem('Remove All Breakpoints', onSelected: debugger.removeAllBreakpoints),
              ]),
              builder: (context, hovered) => Container(
                color: hovered ? colors.rowHover : null,
                padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                child: Row(
                  children: [
                    DtCheckbox(value: !breakpoint.disabled, onChanged: (on) => debugger.setBreakpointDisabled(breakpoint, !on)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        breakpoint.isLogPoint
                            ? 'log(${breakpoint.logValue})'
                            : breakpoint.isConditional
                            ? 'if (${breakpoint.condition})'
                            : breakpoint.snippet.isEmpty
                            ? 'line ${breakpoint.line}'
                            : breakpoint.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.monoStyle(color: breakpoint.disabled ? colors.textDim : colors.textStrong),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (hovered)
                      DtIconButton(DtGlyph.close, width: 16, height: 16, iconSize: 9, tooltip: 'Remove breakpoint', onPressed: () => debugger.removeBreakpoint(breakpoint))
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('${breakpoint.line}', style: context.monoStyle(color: colors.textDim)),
                      ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _callStack(BuildContext context, PauseState pause) {
    final colors = context.dt;
    return Column(
      children: [
        for (final (index, frame) in pause.frames.indexed)
          DtHover(
            onTap: () => debugger.selectFrame(index),
            onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, [
              DtMenuItem(
                'Copy Stack Trace',
                onSelected: () => Clipboard.setData(
                  ClipboardData(
                    text: [
                      for (final f in pause.frames) '${f.name} (${debugger.sourceForActor(f.sourceActor)?.url ?? '(console)'}:${f.line})',
                    ].join('\n'),
                  ),
                ),
              ),
            ]),
            builder: (context, hovered) {
              final selected = index == pause.selected;
              final source = debugger.sourceForActor(frame.sourceActor);
              final location = source == null || source.isEvaluation ? '(console)' : '${source.fileName}:${frame.line}';
              return Container(
                height: 20,
                color: selected ? colors.selection : hovered ? colors.rowHover : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(frame.name, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: selected ? colors.selectionText : colors.textStrong)),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(location, overflow: TextOverflow.ellipsis, style: context.monoStyle(color: selected ? colors.selectionText : colors.textDim)),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _scopes(BuildContext context, PauseState pause) {
    final colors = context.dt;
    final scopes = pause.scopes;
    if (scopes == null) {
      return Padding(padding: const EdgeInsets.all(8), child: Text('Loading…', style: context.uiStyle(color: colors.textDim)));
    }
    final frame = debugger.selectedFrame?.actor ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 6, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, scope) in scopes.indexed)
            ValueTreeView(
              session: session,
              tree: debugger.objects,
              path: 'scope:$frame:$index',
              entry: ObjectEntry(
                scope.title,
                value: scope.object,
                group: scope.object == null ? [for (final b in scope.bindings) ObjectEntry.property(b)] : null,
              ),
              label: true,
              wrap: false,
            ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _openInnermostScope();
  }

  void _openInnermostScope() {
    debugger.addListener(_expandFirstScope);
    _listening = true;
    _expandFirstScope();
  }

  bool _listening = false;
  Object? _expandedFor;

  // The innermost scope is open as soon as there is one, as in Firefox.
  void _expandFirstScope() {
    final pause = debugger.pause;
    final scopes = pause?.scopes;
    if (pause == null || scopes == null || scopes.isEmpty || identical(scopes, _expandedFor)) return;
    _expandedFor = scopes;
    final path = 'scope:${debugger.selectedFrame?.actor ?? ''}:0';
    final first = scopes.first;
    if (!debugger.objects.isExpanded(path) && first.object == null) {
      debugger.objects.toggle(path, ObjectEntry(first.title, group: [for (final b in first.bindings) ObjectEntry.property(b)]));
    }
  }

  @override
  void deactivate() {
    if (_listening) debugger.removeListener(_expandFirstScope);
    _listening = false;
    super.deactivate();
  }
}

class _NewWatchField extends StatefulWidget {
  const _NewWatchField({required this.onAdd});
  final ValueChanged<String> onAdd;

  @override
  State<_NewWatchField> createState() => _NewWatchFieldState();
}

class _NewWatchFieldState extends State<_NewWatchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: DtTextInput(
      controller: _controller,
      placeholder: 'Add watch expression',
      style: context.monoStyle(color: context.dt.textStrong),
      onSubmitted: (value) {
        _controller.clear();
        widget.onAdd(value);
      },
    ),
  );
}

/// "Go to file": a field over the editor that finds sources by name.
class _QuickOpen extends StatefulWidget {
  const _QuickOpen({required this.sources, required this.onOpen, required this.onClose});

  final List<SourceInfo> sources;
  final void Function(SourceInfo source, int line) onOpen;
  final VoidCallback onClose;

  @override
  State<_QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends State<_QuickOpen> {
  final TextEditingController _controller = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whether the letters of [query] appear in [text] in order.
  static bool _fuzzy(String text, String query) {
    var at = 0;
    for (final unit in query.codeUnits) {
      at = text.indexOf(String.fromCharCode(unit), at) + 1;
      if (at == 0) return false;
    }
    return true;
  }

  (List<SourceInfo>, int) get _results {
    var query = _controller.text.toLowerCase();
    var line = 0;
    final colon = query.lastIndexOf(':');
    if (colon >= 0) {
      line = int.tryParse(query.substring(colon + 1)) ?? 0;
      query = query.substring(0, colon);
    }
    final matches = widget.sources.where((s) => _fuzzy(s.url.toLowerCase(), query)).toList()
      ..sort((a, b) {
        final an = a.fileName.toLowerCase().contains(query) ? 0 : 1;
        final bn = b.fileName.toLowerCase().contains(query) ? 0 : 1;
        return an != bn ? an - bn : a.url.length - b.url.length;
      });
    return (matches.take(12).toList(), line);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final (results, line) = _results;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.popup,
        border: Border.all(color: colors.popupBorder),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: colors.inputBackground, border: Border.all(color: colors.accent)),
            child: DtTextInput(
              controller: _controller,
              autofocus: true,
              placeholder: 'Go to file…  (add :line to go to a line)',
              onChanged: (_) => setState(() => _selected = 0),
              onKey: (event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.escape) {
                  widget.onClose();
                } else if (key == LogicalKeyboardKey.arrowDown && results.isNotEmpty) {
                  setState(() => _selected = (_selected + 1) % results.length);
                } else if (key == LogicalKeyboardKey.arrowUp && results.isNotEmpty) {
                  setState(() => _selected = (_selected - 1) % results.length);
                } else if (key == LogicalKeyboardKey.enter && results.isNotEmpty) {
                  widget.onOpen(results[_selected.clamp(0, results.length - 1)], line);
                } else {
                  return KeyEventResult.ignored;
                }
                return KeyEventResult.handled;
              },
            ),
          ),
          for (final (index, source) in results.indexed)
            DtHover(
              onTap: () => widget.onOpen(source, line),
              builder: (context, hovered) => Container(
                height: 22,
                color: index == _selected ? colors.selection : hovered ? colors.rowHover : null,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Text(source.fileName, style: context.uiStyle(color: index == _selected ? colors.selectionText : colors.textStrong)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(source.url, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: index == _selected ? colors.selectionText : colors.textDim, size: 11)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
