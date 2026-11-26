import 'dart:async';

import 'package:flutter/services.dart';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'network_controller.dart';
import 'object_tree.dart';
import 'remote_value.dart';
import 'session.dart';
import 'tool_controller.dart';

class SourceLocation {
  const SourceLocation(this.url, [this.line = 0, this.column = 0]);
  final String url;
  final int line;
  final int column;

  String get fileName {
    if (url.startsWith('(')) return url;
    final bare = url.split('#').first.split('?').first;
    final parts = bare.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? url : parts.last;
  }

  String get label => line > 0 ? '$fileName:$line:$column' : fileName;
}

class StackEntry {
  const StackEntry(this.function, this.location);
  final String function;
  final SourceLocation location;
}

enum ConsoleEntryKind { message, pageError, command, result, navigation, network, notice }

/// The toggles of the console's filter bar.
enum ConsoleCategory { error, warn, log, info, debug, css, xhr, requests, always }

class ConsoleEntry {
  ConsoleEntry({
    required this.kind,
    required this.category,
    required this.time,
    this.level = 'log',
    this.arguments = const [],
    this.text = '',
    this.location,
    this.stack = const [],
    this.errorName = '',
    this.isPromiseRejection = false,
    this.request,
  });

  static int _nextId = 0;
  final int id = _nextId++;
  final ConsoleEntryKind kind;
  final ConsoleCategory category;
  final DateTime time;
  final String level;
  final List<RemoteValue> arguments;

  /// What the entry says, where it is not made of values.
  final String text;
  final SourceLocation? location;
  final List<StackEntry> stack;
  final String errorName;
  final bool isPromiseRejection;
  final NetworkRequest? request;

  /// How many times in a row the same thing was said.
  int repeat = 1;

  /// The ids of the groups it is inside, outermost first.
  List<int> groups = const [];

  bool get isGroup => level == 'group' || level == 'groupCollapsed';

  /// Plain text, for filtering and copying.
  String get plainText {
    switch (kind) {
      case ConsoleEntryKind.pageError:
        return 'Uncaught ${isPromiseRejection ? '(in promise) ' : ''}'
            '${errorName.isEmpty ? '' : '$errorName: '}$text';
      case ConsoleEntryKind.network:
        return '${request!.method} ${request!.url}';
      case ConsoleEntryKind.result:
      case ConsoleEntryKind.message:
        final values = arguments
            .map((value) => value.describe())
            .join(' ');
        return values.isEmpty ? text : values;
      default:
        return text;
    }
  }

  bool sameAs(ConsoleEntry other) =>
      kind == other.kind &&
      kind != ConsoleEntryKind.command &&
      kind != ConsoleEntryKind.result &&
      kind != ConsoleEntryKind.network &&
      !isGroup &&
      level == other.level &&
      location?.label == other.location?.label &&
      plainText == other.plainText &&
      !arguments.any((value) => value.isObject) &&
      !other.arguments.any((value) => value.isObject);
}

class ConsoleCompletion {
  const ConsoleCompletion(this.matches, this.prefix);
  final List<String> matches;

  /// The end of the input that a match replaces.
  final String prefix;
}

class ConsoleController extends ToolController {
  ConsoleController(super.session);

  /// The objects opened in the output.
  late final ObjectTree objects = ObjectTree(session);

  /// The errors whose stack is open.
  final Set<int> expandedEntries = {};

  void toggleExpanded(int id) {
    if (!expandedEntries.remove(id)) expandedEntries.add(id);
    changed();
  }

  static const int _maxEntries = 10000;
  static const int _maxHistory = 300;

  static const Map<ConsoleCategory, bool> _defaultFilters = {
    ConsoleCategory.error: true,
    ConsoleCategory.warn: true,
    ConsoleCategory.log: true,
    ConsoleCategory.info: true,
    ConsoleCategory.debug: true,
    ConsoleCategory.css: false,
    ConsoleCategory.xhr: false,
    ConsoleCategory.requests: false,
  };

  final List<ConsoleEntry> entries = [];
  final List<int> _openGroups = [];

  /// The groups that are shut.
  final Set<int> collapsedGroups = {};

  /// Counts up with every change, for views that cache what they show.
  int revision = 0;

  int errorCount = 0;
  int warningCount = 0;
  String _filterText = '';

  /// What is being typed, kept while the console is away.
  String draft = '';
  bool editorMode = false;

  List<ConsoleEntry>? _visible;
  int _hiddenCount = 0;

  bool get persistLogs => session.settings.flag('console.persist');
  bool get showTimestamps => session.settings.flag('console.timestamps');
  bool get groupSimilar => session.settings.flag('console.groupSimilar', true);
  bool get autocompletionEnabled =>
      session.settings.flag('console.autocomplete', true);

  void toggleSetting(String name, bool value) {
    session.settings.set('console.$name', value);
    _touch();
  }

  List<String> get history => session.settings.strings('console.history');

  String get filterText => _filterText;
  set filterText(String value) {
    _filterText = value;
    _touch();
  }

  bool isShown(ConsoleCategory category) {
    if (category == ConsoleCategory.always) return true;
    return session.settings.flag(
      'console.filter.${category.name}',
      _defaultFilters[category] ?? true,
    );
  }

  void setShown(ConsoleCategory category, bool shown) {
    session.settings.set('console.filter.${category.name}', shown);
    _touch();
  }

  /// How many entries the filters hide.
  int get hiddenCount {
    visibleEntries;
    return _hiddenCount;
  }

  List<ConsoleEntry> get visibleEntries {
    final cached = _visible;
    if (cached != null) return cached;
    final matches = _textMatcher(_filterText);
    final visible = <ConsoleEntry>[];
    var hidden = 0;
    for (final entry in entries) {
      if (entry.groups.any(collapsedGroups.contains)) continue;
      final isNetwork = entry.kind == ConsoleEntryKind.network;
      final shown = isNetwork
          ? isShown(ConsoleCategory.requests) ||
                (entry.request!.isXhr && isShown(ConsoleCategory.xhr))
          : isShown(entry.category);
      if (!shown) {
        if (!isNetwork) hidden++;
        continue;
      }
      if (entry.category != ConsoleCategory.always && !matches(entry)) {
        hidden++;
        continue;
      }
      visible.add(entry);
    }
    _hiddenCount = hidden;
    return _visible = visible;
  }

  /// A matcher for the filter box: words that must all be there, `-word` for
  /// ones that must not, or `/a regular expression/`.
  bool Function(ConsoleEntry) _textMatcher(String filter) {
    final trimmed = filter.trim();
    if (trimmed.isEmpty) return (_) => true;
    String haystack(ConsoleEntry entry) =>
        '${entry.plainText} ${entry.location?.url ?? ''}';
    if (trimmed.length > 2 && trimmed.startsWith('/') && trimmed.endsWith('/')) {
      try {
        final pattern = RegExp(trimmed.substring(1, trimmed.length - 1));
        return (entry) => pattern.hasMatch(haystack(entry));
      } on FormatException {
        return (_) => true;
      }
    }
    final words = trimmed.toLowerCase().split(RegExp(r'\s+'));
    return (entry) {
      final text = haystack(entry).toLowerCase();
      return words.every(
        (word) => word.startsWith('-') && word.length > 1
            ? !text.contains(word.substring(1))
            : text.contains(word),
      );
    };
  }

  void _touch() {
    _visible = null;
    revision++;
    changed();
  }

  void clear() {
    entries.clear();
    _openGroups.clear();
    collapsedGroups.clear();
    expandedEntries.clear();
    objects.clear();
    errorCount = 0;
    warningCount = 0;
    _touch();
  }

  void toggleGroup(int id) {
    if (!collapsedGroups.remove(id)) collapsedGroups.add(id);
    _touch();
  }

  void add(ConsoleEntry entry) {
    entry.groups = List.of(_openGroups);
    final last = entries.isEmpty ? null : entries.last;
    if (last != null && groupSimilar && last.sameAs(entry)) {
      last.repeat++;
    } else {
      entries.add(entry);
      if (entries.length > _maxEntries) {
        entries.removeRange(0, entries.length - _maxEntries);
      }
      if (entry.isGroup) {
        _openGroups.add(entry.id);
        if (entry.level == 'groupCollapsed') collapsedGroups.add(entry.id);
      }
    }
    if (entry.category == ConsoleCategory.error) errorCount++;
    if (entry.category == ConsoleCategory.warn) warningCount++;
    _touch();
  }

  void addNetworkRequest(NetworkRequest request) => add(
    ConsoleEntry(
      kind: ConsoleEntryKind.network,
      category: ConsoleCategory.requests,
      time: request.started,
      request: request,
    ),
  );

  /// A request in the list changed.
  void networkChanged() => _touch();

  @override
  void onWillNavigate(String url) {
    if (persistLogs) {
      _openGroups.clear();
      add(
        ConsoleEntry(
          kind: ConsoleEntryKind.navigation,
          category: ConsoleCategory.always,
          time: DateTime.now(),
          text: 'Navigated to $url',
        ),
      );
    } else {
      clear();
    }
  }

  @override
  void onTargetDestroyed() {
    // The objects went with the document, whatever stays in the log.
    objects.clear();
  }

  @override
  void dispose() {
    objects.dispose();
    super.dispose();
  }

  @override
  void onResources(String type, List<Map<String, Object?>> resources) {
    if (type == 'console-message') {
      resources.forEach(_onMessage);
    } else if (type == 'error-message') {
      resources.forEach(_onPageError);
    }
  }

  static DateTime _time(Map<String, Object?> message) =>
      message['timeStamp'] is num
      ? DateTime.fromMillisecondsSinceEpoch(message.integer('timeStamp'))
      : DateTime.now();

  static List<StackEntry> _stackFrames(List<Map<String, Object?>> frames) => [
    for (final frame in frames)
      if (frame.str('filename') != 'unknown')
        StackEntry(
          frame.str('functionName', '<anonymous>'),
          SourceLocation(
            frame.str('filename'),
            frame.integer('lineNumber'),
            frame.integer('columnNumber'),
          ),
        ),
  ];

  void _onMessage(Map<String, Object?> message) {
    final level = message.str('level', 'log');
    if (level == 'groupEnd') {
      if (_openGroups.isNotEmpty) _openGroups.removeLast();
      return;
    }
    var arguments = message.list('arguments').map(RemoteValue.parse).toList();
    final stack = _stackFrames(message.maps('stacktrace'));
    final filename = message.str('filename');
    SourceLocation? location;
    // The engine says "<eval>" for a message it knows no place for.
    if (filename.isNotEmpty && filename != '<eval>' && filename != 'unknown') {
      location = SourceLocation(
        filename,
        message.integer('lineNumber'),
        message.integer('columnNumber'),
      );
    }
    final category = switch (level) {
      'error' || 'logPointError' => ConsoleCategory.error,
      'warn' => ConsoleCategory.warn,
      'info' => ConsoleCategory.info,
      'debug' => ConsoleCategory.debug,
      _ => ConsoleCategory.log,
    };
    if (level == 'trace' && arguments.isEmpty) {
      arguments = const [RemoteValue.string('console.trace()')];
    }
    if ((level == 'group' || level == 'groupCollapsed') && arguments.isEmpty) {
      arguments = const [RemoteValue.string('console.group')];
    }
    add(
      ConsoleEntry(
        kind: ConsoleEntryKind.message,
        category: category,
        level: level,
        time: _time(message),
        arguments: arguments,
        location: location,
        stack: stack,
      ),
    );
  }

  static final RegExp _stackLine = RegExp(r'^(.*)@(.*?):(\d+):(\d+)$');

  static List<StackEntry> parseErrorStack(String stack) {
    final entries = <StackEntry>[];
    for (final line in stack.split('\n')) {
      final match = _stackLine.firstMatch(line.trim());
      if (match == null || match.group(2) == 'unknown') continue;
      entries.add(
        StackEntry(
          match.group(1)!.isEmpty ? '<anonymous>' : match.group(1)!,
          SourceLocation(
            match.group(2)!,
            int.parse(match.group(3)!),
            int.parse(match.group(4)!),
          ),
        ),
      );
    }
    return entries;
  }

  void _onPageError(Map<String, Object?> resource) {
    final error = resource.obj('pageError');
    final preview = error.obj('exception').obj('preview');
    final stack = parseErrorStack(preview.str('stack'));
    add(
      ConsoleEntry(
        kind: ConsoleEntryKind.pageError,
        category: ConsoleCategory.error,
        level: 'error',
        time: _time(error),
        text: preview.str('message'),
        errorName: preview.str('name'),
        isPromiseRejection: error.flag('isPromiseRejection'),
        stack: stack,
        location: stack.isEmpty ? null : stack.first.location,
      ),
    );
  }

  void addNotice(String text, {String level = 'info'}) => add(
    ConsoleEntry(
      kind: ConsoleEntryKind.notice,
      category: ConsoleCategory.always,
      level: level,
      time: DateTime.now(),
      text: text,
    ),
  );

  void _remember(String input) {
    final next = history.toList()
      ..remove(input)
      ..add(input);
    if (next.length > _maxHistory) {
      next.removeRange(0, next.length - _maxHistory);
    }
    session.settings.set('console.history', next, quiet: true);
  }

  static final RegExp _copyCall = RegExp(r'^copy\(([\s\S]*)\)\s*;?$');
  static final RegExp _usesHelpers = RegExp(r'\$0|\$\$?\(|\$x\(|\$_');

  static const String _help = '''
Console helpers:
  \$0           the element selected in the Inspector
  \$(selector)  document.querySelector (unless the page defines \$)
  \$\$(selector) document.querySelectorAll, as an array
  \$x(path)     the nodes an XPath expression finds
  copy(value)   copies a value to the clipboard
  clear()       clears the console
  :help         shows this''';

  Future<void> execute(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    _remember(input);
    add(
      ConsoleEntry(
        kind: ConsoleEntryKind.command,
        category: ConsoleCategory.always,
        time: DateTime.now(),
        text: input,
      ),
    );
    if (RegExp(r'^(console\.)?clear\(\)\s*;?$').hasMatch(trimmed)) {
      clear();
      return;
    }
    if (trimmed == ':help' || trimmed == 'help()') {
      addNotice(_help);
      return;
    }
    final frame = session.debugger.selectedFrame?.actor;
    try {
      if (_copyCall.firstMatch(trimmed)?.group(1) case final expression?
          when frame == null) {
        final text = await session.runInPage(
          'const value = ($expression\n);'
          'if (typeof value === "string") return value;'
          'if (value instanceof Element) return value.outerHTML;'
          'return JSON.stringify(value, null, 2) ?? String(value);',
        );
        await Clipboard.setData(ClipboardData(text: '$text'));
        addNotice('String was copied to clipboard.');
        return;
      }
      if (frame == null && _usesHelpers.hasMatch(trimmed)) {
        await _defineHelpers();
      }
      final outcome = await session.evaluate(input, frameActor: frame);
      add(
        ConsoleEntry(
          kind: ConsoleEntryKind.result,
          category: ConsoleCategory.always,
          level: outcome.threw ? 'error' : 'log',
          time: DateTime.now(),
          arguments: [outcome.value],
        ),
      );
      session.debugger.refreshWatches();
    } on TimeoutException {
      // Script that threw gets no answer: its error is in the log already.
    } on PageScriptError catch (error) {
      addNotice(error.message, level: 'warn');
    } on RdpError catch (error) {
      if (!error.isClosed) addNotice('Could not run: $error', level: 'warn');
    }
  }

  /// Puts the console's helper names in the page, only where the page has
  /// nothing of its own by that name.
  Future<void> _defineHelpers() async {
    final selector = session.inspector.selectedElementSelector;
    final selected = selector == null
        ? 'null'
        : 'document.querySelector(${RemoteValue.quote(selector)})';
    await session.runInPage(
      'const define = (name, get) => {'
      '  const held = Object.getOwnPropertyDescriptor(window, name);'
      '  if (held && !(held.get && held.get.__birdDevTools)) return;'
      '  get.__birdDevTools = true;'
      '  Object.defineProperty(window, name, { configurable: true, get });'
      '};'
      'const chosen = $selected;'
      'define("\$0", () => chosen);'
      'const one = (s, root) => (root || document).querySelector(s);'
      'const all = (s, root) => Array.from((root || document).querySelectorAll(s));'
      'const path = (expression, root) => { const found = document.evaluate(expression, root || document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);'
      '  return Array.from({ length: found.snapshotLength }, (_, i) => found.snapshotItem(i)); };'
      'define("\$", () => one); define("\$\$", () => all); define("\$x", () => path);'
      'return true;',
    );
  }

  Future<ConsoleCompletion?> complete(String text, int cursor) async {
    final console = session.target?.consoleActor;
    if (console == null || session.debugger.isPaused) return null;
    try {
      final response = await session.connection.request(
        console,
        'autocomplete',
        {'text': text, 'cursor': cursor},
        const Duration(seconds: 3),
      );
      final matches = response.strings('matches');
      if (matches.isEmpty) return null;
      return ConsoleCompletion(matches, response.str('matchProp'));
    } on RdpError {
      return null;
    }
  }
}
