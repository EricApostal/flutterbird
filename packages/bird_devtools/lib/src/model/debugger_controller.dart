import 'dart:async';

import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import 'console_controller.dart';
import 'object_tree.dart';
import 'remote_value.dart';
import 'session.dart';
import 'tool_controller.dart';

class SourceInfo {
  SourceInfo({
    required this.actor,
    required this.url,
    required this.isInline,
    required this.startLine,
    required this.length,
    required this.introductionType,
    this.isBlackBoxed = false,
  });

  final String actor;
  final String url;
  final bool isInline;
  final int startLine;
  final int length;
  final String introductionType;
  bool isBlackBoxed;

  /// Script typed into the console, or made by the tools themselves.
  bool get isEvaluation => url.isEmpty || url.startsWith('(');

  String get fileName {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments.where((part) => part.isNotEmpty);
    return segments.isEmpty ? '(index)' : segments.last;
  }

  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.isEmpty) return '${uri.scheme}://';
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}

class SourceText {
  const SourceText(this.text, this.contentType);
  final String text;
  final String contentType;
}

class Breakpoint {
  Breakpoint({
    required this.url,
    required this.line,
    this.column,
    this.condition = '',
    this.logValue = '',
    this.disabled = false,
  });

  factory Breakpoint.fromJson(Map<String, Object?> json) => Breakpoint(
    url: json.str('url'),
    line: json.integer('line'),
    column: json.integerOrNull('column'),
    condition: json.str('condition'),
    logValue: json.str('logValue'),
    disabled: json.flag('disabled'),
  );

  final String url;
  final int line;
  final int? column;
  String condition;
  String logValue;
  bool disabled;

  /// What the source line said, shown in the list.
  String snippet = '';

  bool get isLogPoint => logValue.isNotEmpty;
  bool get isConditional => condition.isNotEmpty;

  Map<String, Object?> toJson() => {
    'url': url,
    'line': line,
    'column': ?column,
    if (condition.isNotEmpty) 'condition': condition,
    if (logValue.isNotEmpty) 'logValue': logValue,
    if (disabled) 'disabled': true,
  };
}

class StackFrameInfo {
  const StackFrameInfo({
    required this.actor,
    required this.displayName,
    required this.sourceActor,
    required this.line,
    required this.column,
    required this.thisValue,
    required this.arguments,
  });

  factory StackFrameInfo.parse(Map<String, Object?> json) {
    final where = json.obj('where');
    return StackFrameInfo(
      actor: json.str('actor'),
      displayName: json.str('displayName'),
      sourceActor: where.str('actor'),
      line: where.integer('line'),
      column: where.integer('column'),
      thisValue: RemoteValue.parse(json['this']),
      arguments: json.list('arguments').map(RemoteValue.parse).toList(),
    );
  }

  final String actor;
  final String displayName;
  final String sourceActor;
  final int line;

  /// Counted from zero.
  final int column;
  final RemoteValue thisValue;
  final List<RemoteValue> arguments;

  String get name => displayName.isEmpty ? '(anonymous)' : displayName;
}

class DebuggerScope {
  const DebuggerScope(this.title, this.bindings, [this.object]);
  final String title;
  final List<RemoteProperty> bindings;

  /// For a scope that is an object, such as the global one.
  final RemoteValue? object;

  static List<DebuggerScope> chain(
    Map<String, Object?> environment,
    RemoteValue thisValue,
  ) {
    final scopes = <DebuggerScope>[];
    Map<String, Object?>? current = environment;
    var first = true;
    while (current != null && current.containsKey('type')) {
      final type = current.str('type');
      final bindings = [
        for (final entry
            in current.obj('bindings').obj('variables').entries)
          RemoteProperty.parse(entry.key, entry.value),
      ]..sort((a, b) => a.name.compareTo(b.name));
      // "this" belongs to the innermost scope, as Firefox shows it.
      if (first && thisValue.kind != RemoteKind.undefined) {
        bindings.insert(
          0,
          RemoteProperty(name: '<this>', value: thisValue),
        );
      }
      first = false;
      final object = current.containsKey('object')
          ? RemoteValue.parse(current['object'])
          : null;
      final function = current.obj('function').str('displayName');
      scopes.add(
        DebuggerScope(
          switch (type) {
            'function' => function.isEmpty ? '(anonymous)' : function,
            'block' => 'Block',
            _ => object?.className == 'WindowProxy' ? 'Window' : 'Object',
          },
          bindings,
          object,
        ),
      );
      current = current.mapOrNull('parent');
    }
    return scopes;
  }
}

class PauseState {
  PauseState(this.reason, this.message, this.exception, this.frames);
  final String reason;
  final String message;
  final RemoteValue? exception;
  List<StackFrameInfo> frames;
  int selected = 0;
  List<DebuggerScope>? scopes;

  String get headline => switch (reason) {
    'breakpoint' => 'Paused on breakpoint',
    'debuggerStatement' => 'Paused on debugger statement',
    'exception' => 'Paused on exception',
    'resumeLimit' => 'Paused while stepping',
    'interrupted' => 'Paused',
    'breakpointConditionThrown' => 'Error with conditional breakpoint',
    _ => 'Paused',
  };
}

/// A request to bring a line of a source into view.
class SourceRevealRequest {
  const SourceRevealRequest(this.url, this.line, this.column, this.serial);
  final String url;
  final int line;
  final int column;
  final int serial;
}

class WatchValue {
  const WatchValue(this.value, {this.failed = false});
  final RemoteValue value;
  final bool failed;
}

class DebuggerController extends ToolController {
  DebuggerController(super.session) {
    _loadBreakpoints();
  }

  /// The objects opened among the scopes and watches.
  late final ObjectTree objects = ObjectTree(session);

  final Map<String, SourceInfo> _sourcesByActor = {};
  final Map<String, Future<SourceText>> _texts = {};
  final Map<String, Set<int>> breakableLines = {};

  final List<Breakpoint> breakpoints = [];
  final List<String> openUrls = [];
  String? selectedUrl;
  SourceRevealRequest? reveal;
  int _revealSerial = 0;
  final Set<String> prettyPrinted = {};

  PauseState? pause;
  bool pauseRequested = false;
  String error = '';

  final List<WatchValue?> watchValues = [];

  bool get isPaused => pause != null;

  StackFrameInfo? get selectedFrame {
    final pause = this.pause;
    if (pause == null || pause.frames.isEmpty) return null;
    return pause.frames[pause.selected.clamp(0, pause.frames.length - 1)];
  }

  /// The scripts of the page, one for each address.
  List<SourceInfo> get sources {
    final byUrl = <String, SourceInfo>{};
    for (final source in _sourcesByActor.values) {
      if (source.isEvaluation) continue;
      final held = byUrl[source.url];
      // A whole file stands for its address ahead of a script inside it.
      if (held == null || (held.isInline && !source.isInline)) {
        byUrl[source.url] = source;
      }
    }
    return byUrl.values.toList()..sort((a, b) => a.url.compareTo(b.url));
  }

  SourceInfo? sourceForActor(String actor) => _sourcesByActor[actor];

  SourceInfo? sourceForUrl(String url) {
    for (final source in sources) {
      if (source.url == url) return source;
    }
    for (final source in _sourcesByActor.values) {
      if (source.url == url) return source;
    }
    return null;
  }

  // ------------------------------------------------------------ sources

  @override
  void onTargetAvailable(DevToolsTarget target) {
    _loadSources(target);
    if (session.settings.flag('debugger.watching', true)) refreshWatches();
  }

  @override
  void onTargetDestroyed() {
    _sourcesByActor.clear();
    _texts.clear();
    breakableLines.clear();
    pause = null;
    pauseRequested = false;
    objects.clear();
    changed();
  }

  @override
  void dispose() {
    objects.dispose();
    super.dispose();
  }

  Future<void> _loadSources(DevToolsTarget target) async {
    try {
      final response = await session.connection.request(
        target.threadActor,
        'sources',
      );
      if (session.target?.actor != target.actor) return;
      response.maps('sources').forEach(_addSource);
      changed();
    } on RdpError {
      // The sources arrive as resources too.
    }
  }

  void _addSource(Map<String, Object?> form) {
    final actor = form.str('actor');
    if (actor.isEmpty || _sourcesByActor.containsKey(actor)) return;
    _sourcesByActor[actor] = SourceInfo(
      actor: actor,
      url: form.str('url'),
      isInline: form.flag('isInlineSource'),
      startLine: form.integer('sourceStartLine', 1),
      length: form.integer('sourceLength'),
      introductionType: form.str('introductionType'),
      isBlackBoxed: form.flag('isBlackBoxed'),
    );
  }

  Future<SourceText> loadSource(SourceInfo source) {
    return _texts[source.actor] ??= () async {
      try {
        final response = await session.connection.request(
          source.actor,
          'source',
        );
        final text = SourceText(
          response.str('source'),
          response.str('contentType'),
        );
        _noteSnippets(source.url, text.text);
        _loadBreakableLines(source);
        return text;
      } catch (_) {
        _texts.remove(source.actor);
        rethrow;
      }
    }();
  }

  Future<void> _loadBreakableLines(SourceInfo source) async {
    try {
      final response = await session.connection.request(
        source.actor,
        'getBreakableLines',
        const {},
        const Duration(seconds: 5),
      );
      // The scripts of a page share its address, and each has its own lines.
      breakableLines.putIfAbsent(source.url, () => {}).addAll([
        for (final line in response.list('lines'))
          if (line is num) line.toInt(),
      ]);
      changed();
    } on RdpError {
      // Every line can then be clicked.
    }
  }

  void _noteSnippets(String url, String text) {
    final mine = breakpoints.where((bp) => bp.url == url).toList();
    if (mine.isEmpty) return;
    final lines = text.split('\n');
    for (final breakpoint in mine) {
      if (breakpoint.line >= 1 && breakpoint.line <= lines.length) {
        breakpoint.snippet = lines[breakpoint.line - 1].trim();
      }
    }
    changed();
  }

  void openSource(String url, {int line = 0, int column = 0}) {
    if (!openUrls.contains(url)) openUrls.add(url);
    selectedUrl = url;
    if (line > 0) {
      reveal = SourceRevealRequest(url, line, column, ++_revealSerial);
    }
    changed();
  }

  /// Shows the place a link in another tool points at.
  void showLocation(SourceLocation location) {
    if (sourceForUrl(location.url) == null) {
      session.onOpenLink?.call(location.url);
      return;
    }
    session.selectTool('debugger');
    openSource(location.url, line: location.line, column: location.column);
  }

  void closeSource(String url) {
    final index = openUrls.indexOf(url);
    if (index < 0) return;
    openUrls.removeAt(index);
    if (selectedUrl == url) {
      selectedUrl = openUrls.isEmpty
          ? null
          : openUrls[index.clamp(0, openUrls.length - 1)];
    }
    changed();
  }

  void togglePrettyPrint(String url) {
    if (!prettyPrinted.remove(url)) prettyPrinted.add(url);
    changed();
  }

  Future<void> setBlackBoxed(SourceInfo source, bool blackBoxed) async {
    try {
      await session.connection.request(
        source.actor,
        blackBoxed ? 'blackbox' : 'unblackbox',
      );
      source.isBlackBoxed = blackBoxed;
      changed();
    } on RdpError catch (failure) {
      error = failure.message;
      changed();
    }
  }

  // ------------------------------------------------------------ breakpoints

  void _loadBreakpoints() {
    breakpoints
      ..clear()
      ..addAll(
        session.settings.maps('debugger.breakpoints').map(Breakpoint.fromJson),
      );
  }

  void _saveBreakpoints() {
    session.settings.set('debugger.breakpoints', [
      for (final breakpoint in breakpoints) breakpoint.toJson(),
    ]);
    changed();
  }

  /// The breakpoint on a line, and, for a line that holds many statements, at
  /// [column] of it.
  Breakpoint? breakpointAt(String url, int line, [int? column]) {
    for (final breakpoint in breakpoints) {
      if (breakpoint.url == url &&
          breakpoint.line == line &&
          (column == null || breakpoint.column == column)) {
        return breakpoint;
      }
    }
    return null;
  }

  Map<String, Object?> _location(Breakpoint breakpoint) => {
    'sourceUrl': breakpoint.url,
    'line': breakpoint.line,
    'column': ?breakpoint.column,
  };

  Future<void> _send(Breakpoint breakpoint, {required bool set}) async {
    final list = session.breakpointListActor;
    if (list == null) return;
    try {
      await session.connection.request(
        list,
        set ? 'setBreakpoint' : 'removeBreakpoint',
        {
          'location': _location(breakpoint),
          'options': {
            if (breakpoint.condition.isNotEmpty)
              'condition': breakpoint.condition,
            if (breakpoint.logValue.isNotEmpty) 'logValue': breakpoint.logValue,
          },
        },
      );
      error = '';
    } on RdpError catch (failure) {
      if (set && !failure.isClosed) error = failure.message;
    }
    changed();
  }

  Future<void> restoreBreakpoints() async {
    for (final breakpoint in List.of(breakpoints)) {
      if (!breakpoint.disabled) await _send(breakpoint, set: true);
    }
  }

  Future<void> addBreakpoint(
    String url,
    int line, {
    int? column,
    String condition = '',
    String logValue = '',
  }) async {
    final existing = breakpointAt(url, line, column);
    if (existing != null) {
      existing
        ..condition = condition
        ..logValue = logValue
        ..disabled = false;
      _saveBreakpoints();
      await _send(existing, set: true);
      return;
    }
    final breakpoint = Breakpoint(
      url: url,
      line: line,
      column: column,
      condition: condition,
      logValue: logValue,
    );
    breakpoints
      ..add(breakpoint)
      ..sort((a, b) {
        final byUrl = a.url.compareTo(b.url);
        return byUrl != 0 ? byUrl : a.line.compareTo(b.line);
      });
    if (sourceForUrl(url) case final source?) {
      final text = await _texts[source.actor];
      if (text != null) _noteSnippets(url, text.text);
    }
    _saveBreakpoints();
    await _send(breakpoint, set: true);
  }

  Future<void> removeBreakpoint(Breakpoint breakpoint) async {
    if (!breakpoints.remove(breakpoint)) return;
    _saveBreakpoints();
    await _send(breakpoint, set: false);
  }

  Future<void> toggleBreakpoint(String url, int line, {int? column}) {
    final existing = breakpointAt(url, line, column);
    return existing == null
        ? addBreakpoint(url, line, column: column)
        : removeBreakpoint(existing);
  }

  Future<void> setBreakpointDisabled(Breakpoint breakpoint, bool disabled) {
    breakpoint.disabled = disabled;
    _saveBreakpoints();
    return _send(breakpoint, set: !disabled);
  }

  Future<void> removeAllBreakpoints() async {
    for (final breakpoint in List.of(breakpoints)) {
      await removeBreakpoint(breakpoint);
    }
  }

  // ------------------------------------------------------------ configuration

  bool get pauseOnDebuggerStatement =>
      session.settings.flag('debugger.pauseOnDebuggerStatement', true);
  bool get pauseOnExceptions =>
      session.settings.flag('debugger.pauseOnExceptions');
  bool get pauseOnCaughtExceptions =>
      session.settings.flag('debugger.pauseOnCaughtExceptions');
  bool get breakpointsActive =>
      session.settings.flag('debugger.breakpointsActive', true);

  Future<void> setOption(String name, bool value) async {
    session.settings.set('debugger.$name', value);
    changed();
    await applyConfiguration();
  }

  Future<void> applyConfiguration() => _configure(
    pauseOnExceptions: pauseOnExceptions,
    ignoreCaught: !pauseOnCaughtExceptions,
    onDebugger: pauseOnDebuggerStatement,
    skip: !breakpointsActive,
  );

  Future<void> _configure({
    required bool pauseOnExceptions,
    required bool ignoreCaught,
    required bool onDebugger,
    required bool skip,
  }) async {
    final actor = session.threadConfigurationActor;
    if (actor == null) return;
    try {
      await session.connection.request(actor, 'updateConfiguration', {
        'configuration': {
          'pauseOnExceptions': pauseOnExceptions,
          'ignoreCaughtExceptions': ignoreCaught,
          'shouldPauseOnDebuggerStatement': onDebugger,
          'skipBreakpoints': skip,
        },
      });
    } on RdpError {
      // The connection is going.
    }
  }

  /// Leaves a page that nothing will stop again: a page paused with no
  /// debugger listening would never run again.
  void release() {
    final thread = session.target?.threadActor;
    _configure(
      pauseOnExceptions: false,
      ignoreCaught: true,
      onDebugger: false,
      skip: true,
    );
    final list = session.breakpointListActor;
    if (list != null) {
      for (final breakpoint in breakpoints.where((bp) => !bp.disabled)) {
        session.connection.notify(list, 'removeBreakpoint', {
          'location': _location(breakpoint),
        });
      }
    }
    if (thread != null && isPaused) {
      session.connection.notify(thread, 'resume');
    }
  }

  // ------------------------------------------------------------ pausing

  @override
  void onResources(String type, List<Map<String, Object?>> resources) {
    if (type == 'source') {
      resources.forEach(_addSource);
      changed();
    } else if (type == 'thread-state') {
      for (final resource in resources) {
        if (resource.str('state') == 'paused') {
          _didPause(resource);
        } else {
          pause = null;
          // The objects of a pause end with it.
          objects.clear();
          changed();
        }
      }
    }
  }

  Future<void> _didPause(Map<String, Object?> resource) async {
    final why = resource.obj('why');
    final youngest = StackFrameInfo.parse(resource.obj('frame'));
    final next = PauseState(
      why.str('type'),
      why.str('message'),
      why.containsKey('exception')
          ? RemoteValue.parse(why['exception'])
          : null,
      [youngest],
    );
    pause = next;
    pauseRequested = false;
    _endRunTo();
    session.selectTool('debugger');
    _revealFrame(youngest);
    changed();
    final thread = session.target?.threadActor;
    if (thread == null) return;
    try {
      final response = await session.connection.request(thread, 'frames', {
        'start': 0,
        'count': 200,
      });
      if (pause != next) return;
      final frames = response.maps('frames').map(StackFrameInfo.parse).toList();
      if (frames.isNotEmpty) next.frames = frames;
      changed();
    } on RdpError {
      // Resumed in the meantime.
    }
    await _loadScopes(next);
    refreshWatches();
  }

  void _revealFrame(StackFrameInfo frame) {
    final source = _sourcesByActor[frame.sourceActor];
    if (source != null) {
      openSource(source.url, line: frame.line, column: frame.column);
    }
  }

  void selectFrame(int index) {
    final pause = this.pause;
    if (pause == null || index < 0 || index >= pause.frames.length) return;
    pause
      ..selected = index
      ..scopes = null;
    _revealFrame(pause.frames[index]);
    changed();
    _loadScopes(pause).then((_) => refreshWatches());
  }

  Future<void> _loadScopes(PauseState state) async {
    final index = state.selected;
    if (pause != state || index >= state.frames.length) return;
    final frame = state.frames[index];
    try {
      final environment = await session.connection.request(
        frame.actor,
        'getEnvironment',
      );
      if (pause != state || state.selected != index) return;
      state.scopes = DebuggerScope.chain(environment, frame.thisValue);
      changed();
    } on RdpError {
      // Resumed in the meantime.
    }
  }

  Future<void> _resume([String? limit]) async {
    final thread = session.target?.threadActor;
    if (thread == null || pause == null) return;
    try {
      await session.connection.request(thread, 'resume', {
        if (limit != null) 'resumeLimit': {'type': limit},
      });
    } on RdpError {
      // Already running.
    }
  }

  Future<void> resume() => _resume();
  Future<void> stepOver() => _resume('next');
  Future<void> stepIn() => _resume('step');
  Future<void> stepOut() => _resume('finish');

  Breakpoint? _runTo;

  /// Resumes, stopping when execution reaches a line.
  Future<void> continueTo(String url, int line, {int? column}) async {
    if (breakpointAt(url, line, column) == null) {
      final once = Breakpoint(url: url, line: line, column: column);
      _runTo = once;
      await _send(once, set: true);
    }
    await resume();
  }

  void _endRunTo() {
    final once = _runTo;
    _runTo = null;
    if (once != null) _send(once, set: false);
  }

  /// Pauses before the next script that runs.
  Future<void> interrupt() async {
    final thread = session.target?.threadActor;
    if (thread == null || isPaused) return;
    pauseRequested = true;
    changed();
    try {
      await session.connection.request(thread, 'interrupt', {
        'when': 'onNext',
      });
    } on RdpError {
      pauseRequested = false;
      changed();
    }
  }

  // ------------------------------------------------------------ watches

  List<String> get watches => session.settings.strings('debugger.watches');

  void addWatch(String expression) {
    if (expression.trim().isEmpty) return;
    session.settings.set('debugger.watches', [...watches, expression.trim()]);
    refreshWatches();
  }

  void setWatch(int index, String expression) {
    final next = watches.toList();
    if (index >= next.length) return;
    expression.trim().isEmpty
        ? next.removeAt(index)
        : next[index] = expression.trim();
    session.settings.set('debugger.watches', next);
    refreshWatches();
  }

  void removeAllWatches() {
    session.settings.set('debugger.watches', <String>[]);
    refreshWatches();
  }

  int _watchGeneration = 0;

  Future<void> refreshWatches() async {
    final expressions = watches;
    final generation = ++_watchGeneration;
    watchValues
      ..length = 0
      ..addAll(List.filled(expressions.length, null));
    changed();
    for (var i = 0; i < expressions.length; i++) {
      final frame = selectedFrame?.actor;
      WatchValue value;
      try {
        final outcome = await session.evaluate(
          frame != null
              ? expressions[i]
              : '(() => { try { return eval(${RemoteValue.quote(expressions[i])}); } catch (error) { return String(error); } })()',
          frameActor: frame,
          timeout: const Duration(seconds: 3),
        );
        value = WatchValue(outcome.value, failed: outcome.threw);
      } catch (_) {
        value = const WatchValue(
          RemoteValue.string('(unavailable)'),
          failed: true,
        );
      }
      if (isDisposed || generation != _watchGeneration) return;
      watchValues[i] = value;
      changed();
    }
  }
}
