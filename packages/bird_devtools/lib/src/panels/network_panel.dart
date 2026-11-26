import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/network_controller.dart';
import '../model/session.dart';
import '../ui/code_view.dart';
import '../ui/color_picker.dart';
import '../ui/icons.dart';
import '../ui/json_tree.dart';
import '../ui/menu.dart';
import '../ui/table.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../util/pretty_print.dart';
import '../util/syntax.dart';

/// A size as Firefox writes one.
String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(2)} kB';
  return '${(bytes / 1000000).toStringAsFixed(2)} MB';
}

String formatMillis(num? ms) {
  if (ms == null) return '';
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
  return '${ms.round()} ms';
}

Color statusColor(NetworkRequest request, DtColors colors) {
  final status = request.status;
  if (request.failed) return const Color(0xFFD70022);
  if (status == null) return colors.textDim;
  if (status >= 500) return const Color(0xFFD70022);
  if (status >= 400) return const Color(0xFFE25141);
  if (status >= 300) return const Color(0xFFD7B600);
  return const Color(0xFF30A14E);
}

/// The Network Monitor.
class NetworkPanel extends StatefulWidget {
  const NetworkPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<NetworkPanel> createState() => _NetworkPanelState();
}

class _NetworkPanelState extends State<NetworkPanel> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'network');
  final FocusNode _filterFocus = FocusNode(debugLabel: 'filter URLs');
  int _seen = -1;

  NetworkController get network => widget.session.network;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
    final key = event.logicalKey;
    if (command && key == LogicalKeyboardKey.keyF) {
      _filterFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyK) {
      network.clear();
      return KeyEventResult.handled;
    }
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape && network.selected != null) {
      network.select(null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final visible = network.visibleRequests;
      if (visible.isEmpty) return KeyEventResult.handled;
      final at = network.selected == null ? -1 : visible.indexOf(network.selected!);
      final next = (at + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, visible.length - 1);
      network.select(visible[next]);
      if (_scroll.hasClients) {
        final position = _scroll.position;
        final top = next * 22.0;
        if (top < position.pixels) {
          _scroll.jumpTo(top);
        } else if (top + 22 > position.pixels + position.viewportDimension) {
          _scroll.jumpTo(top + 22 - position.viewportDimension);
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: network,
      builder: (context, _) {
        _followNewRequests();
        final selected = network.selected;
        return ColoredBox(
          color: context.dt.body,
          child: Column(
            children: [
              _toolbar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 760;
                    return DtSplit(
                      axis: narrow ? Axis.vertical : Axis.horizontal,
                      initialSize: narrow ? constraints.maxHeight * 0.55 : constraints.maxWidth * 0.46,
                      minSize: narrow ? 100 : 300,
                      minOther: narrow ? 60 : 240,
                      settings: widget.session.settings,
                      settingKey: narrow ? 'network.detailsHeight' : 'network.detailsWidth',
                      showSecond: selected != null,
                      first: _list(context),
                      second: selected == null ? const SizedBox.shrink() : RequestDetails(session: widget.session, request: selected),
                    );
                  },
                ),
              ),
              _footer(context),
            ],
          ),
        );
      },
    ),
  );

  void _followNewRequests() {
    if (_seen == network.requests.length) return;
    final grew = network.requests.length > _seen;
    _seen = network.requests.length;
    if (!grew || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 4) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  static const _categories = [
    (NetworkCategory.html, 'HTML'),
    (NetworkCategory.css, 'CSS'),
    (NetworkCategory.js, 'JS'),
    (NetworkCategory.xhr, 'XHR'),
    (NetworkCategory.fonts, 'Fonts'),
    (NetworkCategory.images, 'Images'),
    (NetworkCategory.media, 'Media'),
    (NetworkCategory.websocket, 'WS'),
    (NetworkCategory.other, 'Other'),
  ];

  List<Widget> _chips() {
    final chosen = network.categories;
    bool additive() => HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
    return [
      DtChip('All', selected: chosen.isEmpty, onTap: () => network.chooseCategory(null)),
      for (final (category, label) in _categories)
        DtChip(
          label,
          selected: chosen.contains(category),
          tooltip: '⌘-click to select several',
          onTap: () => network.chooseCategory(category, additive: additive()),
        ),
    ];
  }

  Widget _toolbar(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1080;
      return Column(
        children: [
          DtToolbar(
            children: [
              DtIconButton(DtGlyph.trash, tooltip: 'Clear (⌘K)', onPressed: network.clear),
              const DtToolbarSeparator(),
              Expanded(
                child: DtSearchBox(
                  value: network.filterText,
                  focusNode: _filterFocus,
                  placeholder: 'Filter URLs',
                  onChanged: (value) => network.filterText = value,
                ),
              ),
              const DtToolbarSeparator(),
              DtIconButton(
                network.recording ? DtGlyph.pause : DtGlyph.play,
                tooltip: network.recording ? 'Pause recording network log' : 'Resume recording network log',
                active: !network.recording,
                onPressed: () => network.setRecording(!network.recording),
              ),
              if (wide) const DtToolbarSeparator(),
              if (wide) ..._chips(),
              const DtToolbarSeparator(),
              DtCheckbox(label: 'Persist Logs', value: network.persistLogs, onChanged: (on) => network.persistLogs = on),
              const SizedBox(width: 8),
              DtDropdown(
                label: 'HAR',
                tooltip: 'HTTP Archive',
                entries: () => [
                  DtMenuItem('Copy All As HAR', enabled: network.requests.isNotEmpty, onSelected: () => Clipboard.setData(ClipboardData(text: network.exportHar()))),
                  DtMenuItem(
                    'Save All As HAR',
                    enabled: network.requests.isNotEmpty && widget.session.onSaveFile != null,
                    onSelected: () => widget.session.onSaveFile?.call('network.har', utf8.encode(network.exportHar())),
                  ),
                ],
              ),
            ],
          ),
          if (!wide)
            DtToolbar(
              height: 24,
              children: [
                Expanded(
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _chips())),
                ),
              ],
            ),
        ],
      );
    },
  );

  List<DtMenuEntry> _requestMenu(NetworkRequest request) {
    void copy(String text) => Clipboard.setData(ClipboardData(text: text));
    Future<void> withDetails(String Function() text) async {
      await network.loadDetails(request, content: true);
      copy(text());
    }

    return [
      DtMenuItem('Copy URL', onSelected: () => copy(request.url)),
      DtMenuItem(
        'Copy Value',
        submenu: [
          DtMenuItem('Copy as cURL', onSelected: () => withDetails(() => request.asCurl)),
          DtMenuItem('Copy as Fetch', onSelected: () => withDetails(() => request.asFetch)),
          DtMenuItem('Copy Request Headers', onSelected: () => withDetails(() => request.headersText(request.requestHeaders))),
          DtMenuItem('Copy Response Headers', onSelected: () => withDetails(() => request.headersText(request.responseHeaders))),
          DtMenuItem('Copy POST Data', enabled: request.method != 'GET', onSelected: () => withDetails(() => request.postData ?? '')),
          DtMenuItem('Copy Response', onSelected: () => withDetails(() => request.content?.asText ?? '')),
        ],
      ),
      const DtMenuItem.separator(),
      DtMenuItem('Open in New Tab', enabled: widget.session.onOpenLink != null, onSelected: () => widget.session.onOpenLink?.call(request.url)),
      DtMenuItem('Resend', onSelected: () => network.resend(request)),
      DtMenuItem(
        'Use in Console',
        onSelected: () {
          widget.session.console.draft = 'await fetch(${jsonEncode(request.url)})';
          widget.session.selectTool('console');
        },
      ),
      const DtMenuItem.separator(),
      DtMenuItem('Copy All As HAR', onSelected: () => copy(network.exportHar())),
      DtMenuItem('Clear', onSelected: network.clear),
    ];
  }

  static const _columns = [
    DtColumn('status', 'Status', 64),
    DtColumn('method', 'Method', 58),
    DtColumn('domain', 'Domain', 130),
    DtColumn('file', 'File', 200, minWidth: 140),
    DtColumn('initiator', 'Initiator', 84),
    DtColumn('type', 'Type', 58),
    DtColumn('transferred', 'Transferred', 84, alignRight: true),
    DtColumn('size', 'Size', 72, alignRight: true),
    DtColumn('duration', 'Duration', 70, alignRight: true, hiddenByDefault: true),
    DtColumn('waterfall', 'Waterfall', 240, minWidth: 100),
  ];

  Widget _list(BuildContext context) {
    final colors = context.dt;
    final requests = network.visibleRequests;
    if (network.requests.isEmpty) {
      return DtEmptyState(
        '• Perform a request or Reload the page to see detailed information about network activity.',
        actions: [DtButton('Reload', glyph: DtGlyph.reload, onPressed: widget.session.reload)],
      );
    }
    final details = network.selected != null;
    // The waterfall's scale: from the first request to the end of the last.
    DateTime? first;
    for (final request in requests) {
      if (first == null || request.started.isBefore(first)) first = request.started;
    }
    var span = network.finishTime.inMicroseconds / 1000;
    if ((network.loadMs ?? 0) > span) span = network.loadMs!.toDouble();
    if (span < 50) span = 50;

    return DtTable(
      columns: details ? _columns.where((c) => const {'status', 'method', 'domain', 'file', 'type'}.contains(c.id)).toList() : _columns,
      flexColumn: 'file',
      settings: widget.session.settings,
      settingKey: details ? 'network.compact' : 'network.table',
      controller: _scroll,
      sortColumn: network.sortColumn,
      sortAscending: network.sortAscending,
      onSort: network.sortBy,
      rowCount: requests.length,
      headerBuilder: (context, column, width) => column != 'waterfall'
          ? null
          : CustomPaint(
              size: Size(width, 22),
              painter: _TimelinePainter(span, colors, context.uiStyle(size: 10, color: colors.textDim)),
            ),
      rowBuilder: (context, index, cells) {
        final request = requests[index];
        final selected = network.selected == request;
        return DtHover(
          onSecondaryTapDown: (details) => showDtMenu(context, details.globalPosition, _requestMenu(request)),
          builder: (context, hovered) => Listener(
            onPointerDown: (_) {
              _focus.requestFocus();
              network.select(request);
            },
            child: ColoredBox(
              color: selected ? colors.selection : hovered ? colors.rowHover : index.isOdd ? colors.rowAlternate : colors.body,
              child: cells,
            ),
          ),
        );
      },
      cellBuilder: (context, index, column) {
        final request = requests[index];
        final selected = network.selected == request;
        final color = selected
            ? colors.selectionText
            : request.isError
            ? (colors.isDark ? colors.errorText : const Color(0xFFD70022))
            : colors.textStrong;
        Widget text(String value, {bool dim = false}) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.uiStyle(color: dim && !selected ? colors.textDim : color, size: 11),
        );
        switch (column) {
          case 'status':
            return Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor(request, colors),
                    shape: (request.status ?? 0) >= 300 && (request.status ?? 0) < 400 ? BoxShape.rectangle : BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(child: text(request.failed ? '' : '${request.status ?? ''}')),
              ],
            );
          case 'method':
            return text(request.method);
          case 'domain':
            return DtTooltip(message: request.host, child: text(request.host));
          case 'file':
            return DtTooltip(message: request.url, child: text(request.fileName));
          case 'initiator':
            return text(request.causeType, dim: true);
          case 'type':
            return text(request.typeLabel);
          case 'transferred':
            return text(
              request.fromCache
                  ? 'cached'
                  : request.failed
                  ? 'blocked'
                  : formatBytes(request.transferredSize),
              dim: request.fromCache,
            );
          case 'size':
            return text(formatBytes(request.contentSize));
          case 'duration':
            return text(formatMillis(request.totalMs));
          default:
            return CustomPaint(
              size: const Size(double.infinity, 22),
              painter: _WaterfallPainter(
                start: request.started.difference(first!).inMicroseconds / 1000,
                duration: request.totalMs,
                span: span,
                domContentLoaded: _relative(network.domContentLoadedMs, first),
                load: _relative(network.loadMs, first),
                color: selected ? colors.selectionText : const Color(0xFF7BB8F4),
                label: request.totalMs == null ? '' : formatMillis(request.totalMs),
                style: context.uiStyle(size: 10, color: selected ? colors.selectionText : colors.textDim),
              ),
            );
        }
      },
    );
  }

  /// A page timing as the waterfall measures: from the first request.
  double? _relative(int? ms, DateTime? first) {
    final start = network.navigationStart;
    if (ms == null || first == null) return null;
    if (start == null) return ms.toDouble();
    return ms - first.difference(start).inMicroseconds / 1000;
  }

  Widget _footer(BuildContext context) {
    final colors = context.dt;
    final count = network.visibleRequests.length;
    Widget item(String text, [Color? color]) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(text, maxLines: 1, style: context.uiStyle(color: color ?? colors.text, size: 11)),
    );
    return DtToolbar(
      height: 23,
      topBorder: true,
      bottomBorder: false,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                DtIcon(DtGlyph.stopwatch, size: 12, color: colors.textDim),
                if (count == 0)
                  item('No requests')
                else ...[
                  item(count == 1 ? '1 request' : '$count requests'),
                  item('${formatBytes(network.totalContentSize)} / ${formatBytes(network.totalTransferredSize)} transferred'),
                  item('Finish: ${formatMillis(network.finishTime.inMicroseconds / 1000)}'),
                  if (network.domContentLoadedMs case final ms?) item('DOMContentLoaded: ${formatMillis(ms)}', colors.blue),
                  if (network.loadMs case final ms?) item('load: ${formatMillis(ms)}', const Color(0xFFD70022)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.span, this.colors, this.style);
  final double span;
  final DtColors colors;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - 8;
    if (width <= 0) return;
    var step = 1.0;
    for (final candidate in [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 30000.0, 60000.0]) {
      step = candidate;
      if (candidate / span * width >= 56) break;
    }
    final line = Paint()..color = colors.splitter;
    for (var at = 0.0; at < span; at += step) {
      final x = 4 + at / span * width;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height), line);
      final painter = TextPainter(
        text: TextSpan(text: formatMillis(at), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (x + 3 + painter.width < size.width) painter.paint(canvas, Offset(x + 3, 5));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.span != span || old.colors != colors;
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.start,
    required this.duration,
    required this.span,
    required this.domContentLoaded,
    required this.load,
    required this.color,
    required this.label,
    required this.style,
  });

  final double start;
  final double? duration;
  final double span;
  final double? domContentLoaded;
  final double? load;
  final Color color;
  final String label;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - 4;
    if (width <= 0) return;
    double x(double ms) => (ms / span * width).clamp(0, width);
    void mark(double? at, Color color) {
      if (at == null || at < 0 || at > span) return;
      canvas.drawRect(Rect.fromLTWH(x(at), 0, 1, size.height), Paint()..color = color);
    }

    mark(domContentLoaded, const Color(0x990060DF));
    mark(load, const Color(0x99D70022));
    final from = x(start);
    var to = x(start + (duration ?? 0));
    if (to < from + 3) to = from + 3;
    canvas.drawRRect(
      RRect.fromLTRBR(from, size.height / 2 - 4, to, size.height / 2 + 4, const Radius.circular(1)),
      Paint()..color = duration == null ? color.withValues(alpha: 0.4) : color,
    );
    if (label.isEmpty) return;
    final painter = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr)..layout();
    final labelX = to + 4 + painter.width > size.width ? from - painter.width - 4 : to + 4;
    painter.paint(canvas, Offset(labelX, (size.height - painter.height) / 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_WaterfallPainter old) =>
      old.start != start || old.duration != duration || old.span != span || old.color != color ||
      old.load != load || old.domContentLoaded != domContentLoaded;
}

/// The sidebar about one request.
class RequestDetails extends StatefulWidget {
  const RequestDetails({super.key, required this.session, required this.request});

  final ToolboxSession session;
  final NetworkRequest request;

  @override
  State<RequestDetails> createState() => _RequestDetailsState();
}

class _RequestDetailsState extends State<RequestDetails> {
  String _filter = '';
  final Set<String> _closed = {};
  final Set<String> _raw = {};
  final FocusNode _selectionFocus = FocusNode(debugLabel: 'request details');

  NetworkRequest get request => widget.request;
  NetworkController get network => widget.session.network;

  @override
  void didUpdateWidget(RequestDetails old) {
    super.didUpdateWidget(old);
    if (old.request != request) _filter = '';
  }

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final tabs = [
      ('headers', 'Headers'),
      ('cookies', 'Cookies'),
      ('request', 'Request'),
      ('response', 'Response'),
      ('timings', 'Timings'),
      if (request.uri?.scheme == 'https') ('security', 'Security'),
    ];
    var selected = network.detailTab;
    if (!tabs.any((t) => t.$1 == selected)) selected = 'headers';
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        children: [
          DtSidebarTabs(
            tabs: tabs,
            selected: selected,
            onSelect: (tab) => setState(() {
              network.detailTab = tab;
              _filter = '';
            }),
            leading: DtIconButton(DtGlyph.close, iconSize: 10, tooltip: 'Close', onPressed: () => network.select(null)),
          ),
          if (request.detailsError case final error?)
            Container(
              width: double.infinity,
              color: colors.warningBackground,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(error, style: context.uiStyle(color: colors.warningText, size: 11)),
            ),
          Expanded(
            child: switch (selected) {
              'cookies' => _cookies(context),
              'request' => _requestBody(context),
              'response' => _response(context),
              'timings' => _timings(context),
              'security' => const DtEmptyState('The engine does not report connection security details over DevTools.'),
              _ => _headers(context),
            },
          ),
        ],
      ),
    );
  }

  Widget _filterBar(String placeholder, {List<Widget> actions = const []}) => DtToolbar(
    height: 26,
    children: [
      Expanded(
        child: DtSearchBox(
          key: ValueKey('${request.actor} $placeholder'),
          value: _filter,
          placeholder: placeholder,
          onChanged: (value) => setState(() => _filter = value),
        ),
      ),
      ...actions,
    ],
  );

  bool _passes(String name, String value) =>
      _filter.isEmpty || name.toLowerCase().contains(_filter.toLowerCase()) || value.toLowerCase().contains(_filter.toLowerCase());

  Widget _pair(BuildContext context, String name, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 1, 8, 1),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$name: ', style: TextStyle(color: context.dt.blue, fontWeight: FontWeight.w600)),
          TextSpan(text: value, style: TextStyle(color: valueColor)),
        ],
      ),
      style: context.monoStyle(color: context.dt.textStrong),
    ),
  );

  Widget _group(BuildContext context, String id, String title, Widget child, {List<Widget> actions = const []}) => DtAccordion(
    title: title,
    header: false,
    expanded: !_closed.contains(id),
    onToggle: () => setState(() => _closed.contains(id) ? _closed.remove(id) : _closed.add(id)),
    actions: actions,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: SizedBox(width: double.infinity, child: child)),
  );

  Widget _selectable(Widget child) => SelectableRegion(
    focusNode: _selectionFocus,
    selectionControls: emptyTextSelectionControls,
    contextMenuBuilder: (context, state) => const SizedBox.shrink(),
    child: child,
  );

  Widget _headers(BuildContext context) {
    final colors = context.dt;
    Widget headerGroup(String id, String title, List<HttpHeader>? headers, String statusLine) {
      final raw = _raw.contains(id);
      var size = 0;
      for (final header in headers ?? const <HttpHeader>[]) {
        size += header.name.length + header.value.length + 4;
      }
      return _group(
        context,
        id,
        '$title (${formatBytes(size)})',
        headers == null
            ? Padding(padding: const EdgeInsets.only(left: 22), child: Text('Loading…', style: context.uiStyle(color: colors.textDim)))
            : raw
            ? Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 8, 2),
                child: Text('$statusLine\n${request.headersText(headers)}', style: context.monoStyle(color: colors.textStrong)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final header in headers)
                    if (_passes(header.name, header.value)) _pair(context, header.name, header.value),
                ],
              ),
        actions: [
          DtCheckbox(label: 'Raw', value: raw, onChanged: (on) => setState(() => on ? _raw.add(id) : _raw.remove(id))),
        ],
      );
    }

    final version = request.httpVersion.isEmpty ? 'HTTP/1.1' : request.httpVersion;
    return Column(
      children: [
        _filterBar(
          'Filter Headers',
          actions: [
            const SizedBox(width: 4),
            DtButton('Resend', glyph: DtGlyph.reload, onPressed: () => network.resend(request)),
          ],
        ),
        Expanded(
          child: _selectable(
            ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${request.method}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: request.url),
                      ],
                    ),
                    style: context.monoStyle(color: colors.textStrong),
                  ),
                ),
                if (request.status != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                    child: Row(
                      children: [
                        SizedBox(width: 110, child: Text('Status', style: context.uiStyle(color: colors.textDim))),
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor(request, colors), shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Flexible(child: Text('${request.status} ${request.statusText}', style: context.uiStyle(color: colors.textStrong))),
                      ],
                    ),
                  ),
                for (final (name, value) in [
                  ('Version', version),
                  ('Transferred', '${formatBytes(request.transferredSize)} (${formatBytes(request.contentSize)} size)'),
                  ('Referrer Policy', request.referrerPolicy),
                  ('Request Priority', request.priority < 0 ? 'High' : request.priority > 0 ? 'Low' : 'Normal'),
                ])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                    child: Row(
                      children: [
                        SizedBox(width: 110, child: Text(name, style: context.uiStyle(color: colors.textDim))),
                        Expanded(child: Text(value, style: context.uiStyle(color: colors.textStrong))),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                headerGroup('response', 'Response Headers', request.responseHeaders, '$version ${request.status ?? ''} ${request.statusText}'),
                headerGroup('requestHeaders', 'Request Headers', request.requestHeaders, '${request.method} ${request.uri?.path ?? ''} $version'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cookies(BuildContext context) {
    final response = request.responseCookies;
    final sent = request.requestCookies;
    if (response.isEmpty && sent.isEmpty) return const DtEmptyState('No cookies for this request');
    return Column(
      children: [
        _filterBar('Filter Cookies'),
        Expanded(
          child: _selectable(
            ListView(
              children: [
                if (response.isNotEmpty)
                  _group(
                    context,
                    'responseCookies',
                    'Response Cookies',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final cookie in response)
                          if (_passes(cookie.name, cookie.value)) ...[
                            _pair(context, cookie.name, cookie.value),
                            for (final attribute in cookie.attributes.entries)
                              Padding(padding: const EdgeInsets.only(left: 16), child: _pair(context, attribute.key, attribute.value)),
                          ],
                      ],
                    ),
                  ),
                if (sent.isNotEmpty)
                  _group(
                    context,
                    'requestCookies',
                    'Request Cookies',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final cookie in sent)
                          if (_passes(cookie.name, cookie.value)) _pair(context, cookie.name, cookie.value),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _requestBody(BuildContext context) {
    final query = request.uri?.queryParametersAll ?? const <String, List<String>>{};
    final body = request.postData ?? '';
    if (query.isEmpty && body.isEmpty) {
      return const DtEmptyState('No payload for this request');
    }
    final json = tryDecodeJson(body);
    Map<String, String>? form;
    final type = request.header(request.requestHeaders, 'content-type') ?? '';
    if (type.contains('x-www-form-urlencoded') && body.isNotEmpty) {
      try {
        form = Uri.splitQueryString(body);
      } catch (_) {
        form = null;
      }
    }
    return Column(
      children: [
        _filterBar('Filter Request Parameters'),
        Expanded(
          child: _selectable(
            ListView(
              children: [
                if (query.isNotEmpty)
                  _group(
                    context,
                    'query',
                    'Query String',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in query.entries)
                          for (final value in entry.value)
                            if (_passes(entry.key, value)) _pair(context, entry.key, value),
                      ],
                    ),
                  ),
                if (body.isNotEmpty)
                  _group(
                    context,
                    'payload',
                    json != null ? 'JSON' : form != null ? 'Form data' : 'Request payload',
                    json != null
                        ? DtJsonTree(value: json, filter: _filter, shrinkWrap: true)
                        : form != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final entry in form.entries)
                                if (_passes(entry.key, entry.value)) _pair(context, entry.key, entry.value),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(body, style: context.monoStyle(color: context.dt.textStrong)),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _response(BuildContext context) {
    final content = request.content;
    if (content == null) {
      if (!request.complete) return const DtEmptyState('The response has not finished arriving.');
      return DtEmptyState(request.detailsError ?? 'Loading…');
    }
    final mime = content.mimeType.toLowerCase();
    if (content.size == 0 && content.text.isEmpty) return const DtEmptyState('No response data available for this request');
    if (mime.startsWith('image/') && !mime.contains('svg')) return _ImagePreview(content: content);
    if (mime.startsWith('font/') || mime.startsWith('audio/') || mime.startsWith('video/')) {
      return DtEmptyState('Binary content: ${content.mimeType}', detail: formatBytes(content.size));
    }
    final text = content.asText;
    if (text == null) return DtEmptyState('This response is not text: ${content.mimeType}', detail: formatBytes(content.size));
    final json = tryDecodeJson(text);
    final raw = _raw.contains('body');
    return Column(
      children: [
        _filterBar(
          json != null && !raw ? 'Filter properties' : 'Search the response',
          actions: [
            const SizedBox(width: 6),
            if (json != null)
              DtCheckbox(label: 'Raw', value: raw, onChanged: (on) => setState(() => on ? _raw.add('body') : _raw.remove('body'))),
            DtIconButton(DtGlyph.copy, tooltip: 'Copy response', onPressed: () => Clipboard.setData(ClipboardData(text: text))),
          ],
        ),
        if (content.truncated)
          Container(
            width: double.infinity,
            color: context.dt.warningBackground,
            padding: const EdgeInsets.all(5),
            child: Text('The response has been truncated.', style: context.uiStyle(color: context.dt.warningText, size: 11)),
          ),
        Expanded(
          child: json != null && !raw
              ? DtJsonTree(value: json, filter: _filter)
              : _SourceText(key: ValueKey(request.actor), text: text, language: languageFor(mime, request.url), needle: _filter),
        ),
      ],
    );
  }

  Widget _timings(BuildContext context) {
    final colors = context.dt;
    final timings = request.timings;
    if (timings == null) {
      return DtEmptyState(request.complete ? request.detailsError ?? 'Loading…' : 'Waiting for the request to finish.');
    }
    const labels = {
      'blocked': ('Blocked', Color(0xFFB1B1B3)),
      'dns': ('DNS Resolution', Color(0xFF00C8D7)),
      'connect': ('Connecting', Color(0xFFD7B600)),
      'ssl': ('TLS Setup', Color(0xFFD76E00)),
      'send': ('Sending', Color(0xFF8000D7)),
      'wait': ('Waiting', Color(0xFFBF4FBF)),
      'receive': ('Receiving', Color(0xFF30A14E)),
    };
    var total = 0.0;
    for (final value in timings.parts.values) {
      total += value;
    }
    var offset = 0.0;
    final rows = <Widget>[];
    for (final entry in timings.parts.entries) {
      final (label, color) = labels[entry.key] ?? (entry.key, colors.textDim);
      final start = total == 0 ? 0.0 : offset / total;
      final length = total == 0 ? 0.0 : entry.value / total;
      offset += entry.value;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text('$label:', style: context.uiStyle(color: colors.textStrong))),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      const SizedBox(height: 11, width: double.infinity),
                      Positioned(
                        left: start * constraints.maxWidth,
                        width: (length * constraints.maxWidth).clamp(entry.value > 0 ? 2 : 0, constraints.maxWidth),
                        top: 0,
                        height: 11,
                        child: ColoredBox(color: color),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 70, child: Text(formatMillis(entry.value), textAlign: TextAlign.right, style: context.uiStyle(color: colors.textDim, size: 11))),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Text('Request Timing  ·  total ${formatMillis(request.totalMs)}', style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
        ),
        ...rows,
      ],
    );
  }
}

/// A response's text, formatted when it came squeezed together.
class _SourceText extends StatefulWidget {
  const _SourceText({super.key, required this.text, required this.language, required this.needle});

  final String text;
  final SyntaxLanguage language;
  final String needle;

  @override
  State<_SourceText> createState() => _SourceTextState();
}

class _SourceTextState extends State<_SourceText> {
  late final List<String> _lines = () {
    if (looksMinified(widget.text)) {
      if (widget.language == SyntaxLanguage.javascript) return prettyPrintJavaScript(widget.text).lines;
      if (widget.language == SyntaxLanguage.css) return prettyPrintCss(widget.text).lines;
    }
    return widget.text.split('\n');
  }();
  late final List<List<Token>> _tokens = highlightLines(_lines, widget.language);

  @override
  Widget build(BuildContext context) => DtCodeView(lines: _lines, tokens: _tokens, needle: widget.needle);
}

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.content});
  final ResponseContent content;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late final Uint8List _bytes = widget.content.bytes;
  Size? _size;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    final stream = MemoryImage(_bytes).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => _size = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      info.dispose();
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CustomPaint(
            painter: _Checker(),
            child: Image.memory(
              _bytes,
              fit: BoxFit.scaleDown,
              errorBuilder: (context, error, stack) => Text('This image cannot be shown.', style: context.uiStyle()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (_size case final size?) 'Dimensions: ${size.width.round()} × ${size.height.round()}',
            'MIME Type: ${widget.content.mimeType}',
            'Size: ${formatBytes(widget.content.size)}',
          ].join('\n'),
          textAlign: TextAlign.center,
          style: context.uiStyle(color: colors.textDim),
        ),
      ],
    );
  }
}

class _Checker extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintCheckerboard(canvas, Offset.zero & size, 8);

  @override
  bool shouldRepaint(_Checker old) => false;
}
