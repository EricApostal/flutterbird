import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/json.dart';

enum DevToolsThemeChoice { auto, light, dark }

enum DevToolsDock { bottom, right, left, window }

/// What the toolbox remembers between openings and across runs. Whoever hosts
/// the toolbox decides where it is kept, with [toJson] and [load].
class DevToolsSettings extends ChangeNotifier {
  DevToolsSettings();

  /// Called a moment after something worth keeping changed.
  void Function(Map<String, Object?> json)? onSave;

  Timer? _saveTimer;
  final Map<String, Object?> _values = {};

  void load(Map<String, Object?> json) {
    _values
      ..clear()
      ..addAll(json);
    notifyListeners();
  }

  Map<String, Object?> toJson() => Map.of(_values);

  /// Keeps [value] under [key]. With [quiet], nothing is told to rebuild: for
  /// what the widget that sets it is already showing.
  void set(String key, Object? value, {bool quiet = false}) {
    if (_values[key] == value && value is! List && value is! Map) return;
    _values[key] = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), flush);
    if (!quiet) notifyListeners();
  }

  /// Saves now what is waiting to be saved.
  void flush() {
    if (_saveTimer == null) return;
    _saveTimer!.cancel();
    _saveTimer = null;
    onSave?.call(toJson());
  }

  @override
  void dispose() {
    flush();
    super.dispose();
  }

  bool flag(String key, [bool fallback = false]) {
    final value = _values[key];
    return value is bool ? value : fallback;
  }

  double number(String key, double fallback) => _values.number(key, fallback);

  String text(String key, [String fallback = '']) =>
      _values.str(key, fallback);

  List<String> strings(String key) => _values.strings(key);

  List<Map<String, Object?>> maps(String key) => _values.maps(key);

  bool has(String key) => _values.containsKey(key);

  DevToolsThemeChoice get theme => DevToolsThemeChoice.values.firstWhere(
    (choice) => choice.name == text('theme'),
    orElse: () => DevToolsThemeChoice.auto,
  );
  set theme(DevToolsThemeChoice value) => set('theme', value.name);

  DevToolsDock get dock => DevToolsDock.values.firstWhere(
    (dock) => dock.name == text('dock'),
    orElse: () => DevToolsDock.bottom,
  );
  set dock(DevToolsDock value) => set('dock', value.name);

  String get panel => text('panel', 'inspector');
  set panel(String value) => set('panel', value);

  bool get splitConsole => flag('splitConsole');
  set splitConsole(bool value) => set('splitConsole', value);

  bool isPanelEnabled(String id) => !strings('disabledPanels').contains(id);

  void setPanelEnabled(String id, bool enabled) {
    final disabled = strings('disabledPanels').toSet();
    enabled ? disabled.remove(id) : disabled.add(id);
    set('disabledPanels', disabled.toList());
  }
}
