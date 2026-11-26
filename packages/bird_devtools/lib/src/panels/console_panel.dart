import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/console_controller.dart';
import '../model/object_tree.dart';
import '../model/remote_value.dart';
import '../model/session.dart';
import '../protocol/json.dart';
import '../ui/code_editor.dart';
import '../ui/code_view.dart';
import '../ui/icons.dart';
import '../ui/inline_editor.dart';
import '../ui/menu.dart';
import '../ui/theme.dart';
import '../ui/value_view.dart';
import '../ui/widgets.dart';
import '../util/syntax.dart';

/// The Web Console: what the page says, and a prompt to say things back.
class ConsolePanel extends StatefulWidget {
  const ConsolePanel({super.key, required this.session, this.autofocus = true});

  final ToolboxSession session;
  final bool autofocus;

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _selectionFocus = FocusNode(debugLabel: 'console output');
  final FocusNode _inputFocus = FocusNode(debugLabel: 'console input');
  bool _followingOutput = true;
  int _seenRevision = -1;

  ConsoleController get console => widget.session.console;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      _followingOutput = position.pixels >= position.maxScrollExtent - 4;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _selectionFocus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // The list is lazy, so its full height is only learnt by going there.
  void _follow([int attempts = 3]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_followingOutput) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels < end) {
        _scroll.jumpTo(end);
        if (attempts > 0) _follow(attempts - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: console,
    builder: (context, _) {
      if (_seenRevision != console.revision) {
        _seenRevision = console.revision;
        _follow();
      }
      final editor = console.editorMode;
      final body = Column(
        children: [
          Expanded(child: _output(context)),
          if (!editor)
            _ConsolePrompt(
              session: widget.session,
              focusNode: _inputFocus,
              autofocus: widget.autofocus,
              onSubmit: _submit,
            ),
        ],
      );
      return ColoredBox(
        color: context.dt.body,
        child: Column(
          children: [
            _toolbar(context),
            Expanded(
              child: editor
                  ? DtSplit(
                      sizeSecond: false,
                      initialSize: 360,
                      minSize: 160,
                      minOther: 160,
                      settings: widget.session.settings,
                      settingKey: 'console.editorWidth',
                      first: _ConsoleEditor(session: widget.session, onSubmit: _submit),
                      second: body,
                    )
                  : body,
            ),
          ],
        ),
      );
    },
  );

  void _submit(String input) {
    _followingOutput = true;
    console.execute(input);
  }

  List<Widget> _categoryChips() {
    Widget chip(ConsoleCategory category, String label, [int count = 0]) => DtChip(
      count > 0 ? '$label ($count)' : label,
      selected: console.isShown(category),
      onTap: () => console.setShown(category, !console.isShown(category)),
    );
    return [
      chip(ConsoleCategory.error, 'Errors', console.errorCount),
      chip(ConsoleCategory.warn, 'Warnings', console.warningCount),
      chip(ConsoleCategory.log, 'Logs'),
      chip(ConsoleCategory.info, 'Info'),
      chip(ConsoleCategory.debug, 'Debug'),
      const DtToolbarSeparator(),
      chip(ConsoleCategory.css, 'CSS'),
      chip(ConsoleCategory.xhr, 'XHR'),
      chip(ConsoleCategory.requests, 'Requests'),
    ];
  }

  Widget _toolbar(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 820;
      final colors = context.dt;
      final hidden = console.hiddenCount;
      final top = <Widget>[
        DtIconButton(
          DtGlyph.trash,
          tooltip: 'Clear the Web Console output (⌘K)',
          onPressed: console.clear,
        ),
        const DtToolbarSeparator(),
        Expanded(
          child: DtSearchBox(
            value: console.filterText,
            placeholder: 'Filter Output',
            onChanged: (text) => console.filterText = text,
            trailing: [
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '$hidden hidden',
                    style: context.uiStyle(color: colors.textDim, size: 11),
                  ),
                ),
            ],
          ),
        ),
        const DtToolbarSeparator(),
        if (wide) ..._categoryChips(),
        if (wide) const DtToolbarSeparator(),
        Builder(
          builder: (context) => DtIconButton(
            DtGlyph.gear,
            tooltip: 'Console Settings',
            onPressed: () => showDtMenuBelow(context, [
              DtMenuItem(
                'Persist Logs',
                checked: console.persistLogs,
                onSelected: () => console.toggleSetting('persist', !console.persistLogs),
              ),
              DtMenuItem(
                'Show Timestamps',
                checked: console.showTimestamps,
                onSelected: () => console.toggleSetting('timestamps', !console.showTimestamps),
              ),
              DtMenuItem(
                'Group Similar Messages',
                checked: console.groupSimilar,
                onSelected: () => console.toggleSetting('groupSimilar', !console.groupSimilar),
              ),
              DtMenuItem(
                'Enable Autocompletion',
                checked: console.autocompletionEnabled,
                onSelected: () => console.toggleSetting('autocomplete', !console.autocompletionEnabled),
              ),
              const DtMenuItem.separator(),
              DtMenuItem(
                'Editor Mode',
                shortcut: '⌘B',
                checked: console.editorMode,
                onSelected: () => setState(() => console.editorMode = !console.editorMode),
              ),
            ]),
          ),
        ),
      ];
      return Column(
        children: [
          DtToolbar(children: top),
          if (!wide)
            DtToolbar(
              height: 24,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _categoryChips()),
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );

  List<DtMenuEntry> _outputMenu(ConsoleEntry? entry, String selected) => [
    if (selected.isNotEmpty)
      DtMenuItem('Copy', shortcut: '⌘C', onSelected: () => Clipboard.setData(ClipboardData(text: selected))),
    if (entry != null)
      DtMenuItem(
        'Copy Message',
        onSelected: () => Clipboard.setData(ClipboardData(text: _exportLine(entry))),
      ),
    DtMenuItem(
      'Export Visible Messages to Clipboard',
      onSelected: () => Clipboard.setData(
        ClipboardData(text: console.visibleEntries.map(_exportLine).join('\n')),
      ),
    ),
    const DtMenuItem.separator(),
    DtMenuItem('Clear Output', shortcut: '⌘K', onSelected: console.clear),
  ];

  static String _exportLine(ConsoleEntry entry) {
    final location = entry.location == null ? '' : ' ${entry.location!.label}';
    return '${entry.plainText}$location';
  }

  String _selected = '';

  Widget _output(BuildContext context) {
    final entries = console.visibleEntries;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          showDtMenu(context, details.globalPosition, _outputMenu(null, _selected)),
      child: SelectableRegion(
        focusNode: _selectionFocus,
        selectionControls: emptyTextSelectionControls,
        onSelectionChanged: (content) => _selected = content?.plainText ?? '',
        contextMenuBuilder: (context, state) => const SizedBox.shrink(),
        child: ListView.builder(
          controller: _scroll,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return GestureDetector(
              key: ValueKey(entry.id),
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (details) =>
                  showDtMenu(context, details.globalPosition, _outputMenu(entry, _selected)),
              child: ConsoleRow(session: widget.session, entry: entry),
            );
          },
        ),
      ),
    );
  }
}

String formatTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}';
}

/// A link to a place in a source, shown at the end of a message.
class SourceLink extends StatelessWidget {
  const SourceLink({super.key, required this.session, required this.location});

  final ToolboxSession session;
  final SourceLocation location;

  @override
  Widget build(BuildContext context) => DtTooltip(
    message: location.url,
    child: DtHover(
      cursor: SystemMouseCursors.click,
      onTap: () => session.debugger.showLocation(location),
      builder: (context, hovered) => Text(
        location.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.monoStyle(
          color: hovered ? context.dt.accent : context.dt.textDim,
          decoration: hovered ? TextDecoration.underline : null,
        ),
      ),
    ),
  );
}

class StackTraceView extends StatelessWidget {
  const StackTraceView({super.key, required this.session, required this.stack});

  final ToolboxSession session;
  final List<StackEntry> stack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final frame in stack)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  frame.function,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.monoStyle(color: context.dt.textStrong),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(child: SourceLink(session: session, location: frame.location)),
            ],
          ),
      ],
    ),
  );
}

/// One entry of the output.
class ConsoleRow extends StatelessWidget {
  const ConsoleRow({super.key, required this.session, required this.entry});

  final ToolboxSession session;
  final ConsoleEntry entry;

  ConsoleController get console => session.console;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final isError = entry.kind != ConsoleEntryKind.result &&
        (entry.level == 'error' || entry.level == 'logPointError');
    final isWarning = entry.level == 'warn';
    final background = isError
        ? colors.errorBackground
        : isWarning
        ? colors.warningBackground
        : null;
    final border = isError
        ? colors.errorBorder
        : isWarning
        ? colors.warningBorder
        : colors.splitter.withValues(alpha: 0.6);

    final Widget? icon = switch (entry.kind) {
      ConsoleEntryKind.command => DtIcon(DtGlyph.command, size: 10, color: colors.textDim),
      ConsoleEntryKind.result => entry.level == 'error'
          ? const DtIcon(DtGlyph.error, size: 11, color: DtColors.errorFill)
          : DtIcon(DtGlyph.result, size: 11, color: colors.textDim),
      ConsoleEntryKind.network => null,
      _ => isError
          ? const DtIcon(DtGlyph.error, size: 11, color: DtColors.errorFill)
          : isWarning
          ? DtIcon(DtGlyph.warning, size: 11, color: colors.warningIcon)
          : entry.level == 'info'
          ? DtIcon(DtGlyph.info, size: 11, color: colors.textDim)
          : entry.level.startsWith('logPoint')
          ? DtIcon(DtGlyph.logpoint, size: 11, color: colors.purple)
          : null,
    };

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 2, 6, 2),
      constraints: const BoxConstraints(minHeight: 21),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (console.showTimestamps)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(formatTime(entry.time), style: context.monoStyle(color: colors.textDim)),
            ),
          SizedBox(
            width: 28,
            height: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (entry.repeat > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isError
                          ? DtColors.errorFill
                          : isWarning
                          ? DtColors.warningFill
                          : DtColors.infoFill,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${entry.repeat}',
                      style: context.uiStyle(color: const Color(0xFFFFFFFF), size: 10),
                    ),
                  )
                else
                  ?icon,
                const SizedBox(width: 6),
              ],
            ),
          ),
          SizedBox(width: entry.groups.length * 14),
          Expanded(child: _body(context, isError, isWarning)),
          if (entry.location case final location?) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: SourceLink(session: session, location: location),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(BuildContext context, bool isError, bool isWarning) {
    final colors = context.dt;
    final textColor = isError
        ? colors.errorText
        : isWarning
        ? colors.warningText
        : colors.textStrong;
    final style = context.monoStyle(color: textColor);
    switch (entry.kind) {
      case ConsoleEntryKind.command:
        final lines = entry.text.split('\n');
        final tokens = highlightLines(lines, SyntaxLanguage.javascript);
        return Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                ...codeSpans(colors, lines[i], tokens[i]),
                if (i + 1 < lines.length) const TextSpan(text: '\n'),
              ],
            ],
          ),
          style: style,
        );
      case ConsoleEntryKind.navigation:
        return Text(entry.text, style: context.monoStyle(color: colors.textDim));
      case ConsoleEntryKind.notice:
        return Text(entry.text, style: style);
      case ConsoleEntryKind.network:
        return _NetworkLine(session: session, entry: entry);
      case ConsoleEntryKind.pageError:
        return _pageError(context, style);
      case ConsoleEntryKind.message:
      case ConsoleEntryKind.result:
        break;
    }

    final arguments = _arguments(context, style);
    if (entry.isGroup) {
      final collapsed = console.collapsedGroups.contains(entry.id);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => console.toggleGroup(entry.id),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 5),
              child: DtIcon(collapsed ? DtGlyph.twistyRight : DtGlyph.twistyDown, size: 8, color: colors.textDim),
            ),
            Expanded(
              child: Text(
                entry.arguments.map((a) => a.describe()).join(' '),
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    if (entry.level == 'table' && entry.arguments.isNotEmpty) {
      final table = _ConsoleTable.from(entry.arguments.first);
      if (table != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [table, arguments],
        );
      }
    }
    if (entry.level == 'trace') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [arguments, StackTraceView(session: session, stack: entry.stack)],
      );
    }
    if (entry.stack.isNotEmpty && (isError || isWarning)) {
      return _expandable(context, arguments);
    }
    return arguments;
  }

  Widget _expandable(BuildContext context, Widget head) {
    final open = console.expandedEntries.contains(entry.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => console.toggleExpanded(entry.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 5, 3),
                child: DtIcon(open ? DtGlyph.twistyDown : DtGlyph.twistyRight, size: 8, color: context.dt.textDim),
              ),
            ),
            Expanded(child: head),
          ],
        ),
        if (open) StackTraceView(session: session, stack: entry.stack),
      ],
    );
  }

  Widget _pageError(BuildContext context, TextStyle style) {
    final head = Text(
      entry.plainText,
      style: style,
    );
    return entry.stack.isEmpty ? head : _expandable(context, head);
  }

  /// A line of values, with what is opened among them under it.
  Widget _arguments(BuildContext context, TextStyle style) {
    final values = entry.arguments;
    // A log's own strings are said as they are; a result is quoted.
    final quoted = entry.kind == ConsoleEntryKind.result;
    if (values.length == 1) {
      return ValueTreeView(
        session: session,
        tree: console.objects,
        path: '${entry.id}:0',
        entry: ObjectEntry('', value: values.first),
        quoted: quoted,
      );
    }
    return ListenableBuilder(
      listenable: console.objects,
      builder: (context, _) {
        final preview = ValuePreview(context.dt);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  for (final (index, value) in values.indexed)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                      child: value.isExpandable
                          ? ValueTreeView(
                              session: session,
                              tree: console.objects,
                              headOnly: true,
                              path: '${entry.id}:$index',
                              entry: ObjectEntry('', value: value),
                            )
                          : Text.rich(
                              TextSpan(children: preview.spans(value, quoted: false)),
                              style: style,
                            ),
                    ),
                ],
              ),
            ),
            for (final (index, value) in values.indexed)
              if (value.isExpandable && console.objects.isExpanded('${entry.id}:$index'))
                for (final (child, item)
                    in (console.objects.childrenOf('${entry.id}:$index') ?? const <ObjectEntry>[]).indexed)
                  ValueTreeView(
                    session: session,
                    tree: console.objects,
                    path: '${entry.id}:$index/$child:${item.name}',
                    entry: item,
                    label: true,
                    depth: 1,
                  ),
          ],
        );
      },
    );
  }
}

/// What console.table shows.
class _ConsoleTable extends StatelessWidget {
  const _ConsoleTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<(String, Map<String, RemoteValue>)> rows;

  static _ConsoleTable? from(RemoteValue value) {
    Map<String, Object?> properties(Map<String, Object?> form) {
      final own = form.obj('ownProperties');
      return own.isNotEmpty ? own : form.obj('preview').obj('ownProperties');
    }

    final top = properties(value.form);
    if (top.isEmpty) return null;
    final columns = <String>{};
    var hasPlainValues = false;
    final rows = <(String, Map<String, RemoteValue>)>[];
    for (final row in top.entries) {
      final descriptor = row.value;
      if (descriptor is! Map<String, Object?>) continue;
      final item = RemoteValue.parse(descriptor['value']);
      final cells = <String, RemoteValue>{};
      final held = item.isObject ? properties(item.form) : const <String, Object?>{};
      for (final cell in held.entries) {
        final inner = cell.value;
        if (inner is! Map<String, Object?> || !inner.containsKey('value')) continue;
        columns.add(cell.key);
        cells[cell.key] = RemoteValue.parse(inner['value']);
      }
      if (cells.isEmpty) {
        hasPlainValues = true;
        cells[''] = item;
      }
      rows.add((row.key, cells));
    }
    if (rows.isEmpty) return null;
    return _ConsoleTable(columns: [...columns, if (hasPlainValues) ''], rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final preview = ValuePreview(colors);
    Widget cell(Widget child, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: child,
    );
    Widget text(String value) =>
        cell(Text(value, style: context.monoStyle(color: colors.textStrong, weight: FontWeight.w700)), header: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: colors.splitter),
          children: [
            TableRow(
              decoration: BoxDecoration(color: colors.toolbar),
              children: [text('(index)'), for (final column in columns) text(column.isEmpty ? 'Values' : column)],
            ),
            for (final (index, values) in rows.take(1000))
              TableRow(
                children: [
                  text(index),
                  for (final column in columns)
                    cell(
                      values.containsKey(column)
                          ? Text.rich(
                              TextSpan(children: preview.spans(values[column]!, depth: 1)),
                              style: context.monoStyle(color: colors.textStrong),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A request, as the console lists it when XHR or Requests are on.
class _NetworkLine extends StatelessWidget {
  const _NetworkLine({required this.session, required this.entry});

  final ToolboxSession session;
  final ConsoleEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final request = entry.request!;
    final status = request.status;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (request.isXhr)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                border: Border.all(color: colors.splitterStrong),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text('XHR', style: context.uiStyle(size: 9, color: colors.textDim)),
            ),
          ),
        Text('${request.method} ', style: context.monoStyle(color: colors.textStrong, weight: FontWeight.w700)),
        Expanded(
          child: DtHover(
            cursor: SystemMouseCursors.click,
            onTap: () {
              session.network.select(request);
              session.selectTool('network');
            },
            builder: (context, hovered) => Text(
              request.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.monoStyle(
                color: colors.blue,
                decoration: hovered ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          status == null
              ? (request.complete ? 'Failed' : 'Pending')
              : '[${request.httpVersion} $status ${request.statusText}'
                    '${request.totalMs == null ? '' : ' ${request.totalMs!.round()}ms'}]',
          style: context.monoStyle(color: request.isError ? colors.errorText : colors.textDim),
        ),
      ],
    );
  }
}

/// The line the user types at.
class _ConsolePrompt extends StatefulWidget {
  const _ConsolePrompt({
    required this.session,
    required this.focusNode,
    required this.onSubmit,
    required this.autofocus,
  });

  final ToolboxSession session;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final bool autofocus;

  @override
  State<_ConsolePrompt> createState() => _ConsolePromptState();
}

class _ConsolePromptState extends State<_ConsolePrompt> {
  late final CodeEditingController _controller = CodeEditingController(
    text: widget.session.console.draft,
    language: SyntaxLanguage.javascript,
  );
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  ConsoleCompletion? _completion;
  int _selected = 0;
  int _historyIndex = -1;
  String _beforeHistory = '';
  int _generation = 0;

  ConsoleController get console => widget.session.console;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hideCompletion() {
    _generation++;
    if (_completion == null) return;
    setState(() => _completion = null);
    _portal.hide();
  }

  Future<void> _complete({bool forced = false}) async {
    if (!console.autocompletionEnabled && !forced) return;
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return _hideCompletion();
    final text = _controller.text;
    final before = text.substring(0, selection.extentOffset);
    // Asked for after a name or a dot, and nowhere else.
    if (!forced && !RegExp(r'[\w$\].]$').hasMatch(before)) return _hideCompletion();
    if (!forced && RegExp(r'(^|[^\w$.])\d+$').hasMatch(before)) return _hideCompletion();
    final generation = ++_generation;
    final completion = await console.complete(text, selection.extentOffset);
    if (!mounted || generation != _generation) return;
    if (completion == null ||
        (completion.matches.length == 1 && completion.matches.first == completion.prefix)) {
      return _hideCompletion();
    }
    setState(() {
      _completion = completion;
      _selected = 0;
    });
    _portal.show();
  }

  void _accept(int index) {
    final completion = _completion;
    if (completion == null) return;
    final cursor = _controller.selection.extentOffset;
    final start = (cursor - completion.prefix.length).clamp(0, cursor);
    final match = completion.matches[index];
    final text = _controller.text.replaceRange(start, cursor, match);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + match.length),
    );
    console.draft = text;
    _hideCompletion();
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    console.draft = text;
  }

  void _walkHistory(int step) {
    final history = console.history;
    if (history.isEmpty) return;
    if (_historyIndex < 0) {
      if (step > 0) return;
      _beforeHistory = _controller.text;
      _historyIndex = history.length - 1;
    } else {
      _historyIndex += step;
    }
    if (_historyIndex >= history.length) {
      _historyIndex = -1;
      _setText(_beforeHistory);
      return;
    }
    if (_historyIndex < 0) _historyIndex = 0;
    _setText(history[_historyIndex]);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final completion = _completion;
    if (completion != null) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selected = (_selected + 1) % completion.matches.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selected = (_selected - 1) % completion.matches.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.arrowRight && _controller.selection.extentOffset == _controller.text.length) {
        _accept(_selected);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter && _selected > 0) {
        _accept(_selected);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _hideCompletion();
        return KeyEventResult.handled;
      }
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.space) {
      _complete(forced: true);
      return KeyEventResult.handled;
    }
    if ((keyboard.isMetaPressed || keyboard.isControlPressed) && key == LogicalKeyboardKey.keyK) {
      console.clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !keyboard.isShiftPressed) {
      final text = _controller.text;
      if (text.trim().isEmpty) return KeyEventResult.handled;
      _hideCompletion();
      _setText('');
      _historyIndex = -1;
      widget.onSubmit(text);
      return KeyEventResult.handled;
    }
    final selection = _controller.selection;
    if (key == LogicalKeyboardKey.arrowUp && selection.isCollapsed &&
        !_controller.text.substring(0, selection.extentOffset.clamp(0, _controller.text.length)).contains('\n')) {
      _walkHistory(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _historyIndex >= 0 && selection.isCollapsed &&
        !_controller.text.substring(selection.extentOffset.clamp(0, _controller.text.length)).contains('\n')) {
      _walkHistory(1);
      return KeyEventResult.handled;
    }
    return handleCodeKeys(_controller, event, (text) => console.draft = text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    _controller.colors = colors;
    final style = context.monoStyle(color: colors.textStrong);
    return Container(
      constraints: const BoxConstraints(maxHeight: 200, minHeight: 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.splitter)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 7, 0),
            child: DtIcon(DtGlyph.prompt, size: 11, color: colors.accent),
          ),
          Expanded(
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) {
                final completion = _completion;
                if (completion == null) return const SizedBox.shrink();
                // Sits above the caret, which the character width finds.
                final cursor = _controller.selection.isValid ? _controller.selection.extentOffset : 0;
                final line = _controller.text.substring(0, cursor).split('\n').last;
                final x = (line.length - completion.prefix.length) * monoCharacterWidth(style);
                return Positioned(
                  left: 0,
                  top: 0,
                  child: CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.topLeft,
                    followerAnchor: Alignment.bottomLeft,
                    offset: Offset(x - 6, -2),
                    child: DtTheme(
                      colors: colors,
                      child: DtCompletionPopup(
                        matches: completion.matches,
                        selected: _selected,
                        typed: completion.prefix.length,
                        onPick: _accept,
                      ),
                    ),
                  ),
                );
              },
              child: CompositedTransformTarget(
                link: _link,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: DtTextInput(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    autofocus: widget.autofocus,
                    style: style,
                    maxLines: null,
                    onKey: _onKey,
                    onChanged: (text) {
                      console.draft = text;
                      _historyIndex = -1;
                      _complete();
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4, top: 1),
            child: DtIconButton(
              DtGlyph.editorMode,
              tooltip: 'Switch to multi-line editor mode (⌘B)',
              onPressed: () {
                console
                  ..editorMode = true
                  ..changed();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The console's multi-line editor, beside the output.
class _ConsoleEditor extends StatefulWidget {
  const _ConsoleEditor({required this.session, required this.onSubmit});

  final ToolboxSession session;
  final ValueChanged<String> onSubmit;

  @override
  State<_ConsoleEditor> createState() => _ConsoleEditorState();
}

class _ConsoleEditorState extends State<_ConsoleEditor> {
  late final CodeEditingController _controller = CodeEditingController(
    text: widget.session.console.draft,
    language: SyntaxLanguage.javascript,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run() {
    if (_controller.text.trim().isNotEmpty) widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.session.console;
    return Column(
      children: [
        DtToolbar(
          height: 26,
          children: [
            DtIconButton(DtGlyph.play, tooltip: 'Run (⌘Enter). The code is not cleared.', onPressed: _run),
            const SizedBox(width: 4),
            Text('⌘ Enter to run', style: context.uiStyle(color: context.dt.textDim, size: 11)),
            const Spacer(),
            DtIconButton(
              DtGlyph.close,
              iconSize: 11,
              tooltip: 'Switch back to inline mode (⌘B)',
              onPressed: () {
                console
                  ..editorMode = false
                  ..changed();
              },
            ),
          ],
        ),
        Expanded(
          child: DtCodeEditor(
            controller: _controller,
            autofocus: true,
            onChanged: (text) => console.draft = text,
            onKey: (event) {
              final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
              if (event is KeyDownEvent && command && event.logicalKey == LogicalKeyboardKey.enter) {
                _run();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          ),
        ),
      ],
    );
  }
}
