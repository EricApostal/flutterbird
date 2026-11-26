import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Which extensions have their button on the toolbar, and in what order. The
/// rest are reached through the extensions button, as in Firefox.
class ToolbarPins {
  ToolbarPins._(this._file, this._pinned, this._known);

  /// Reads what was saved in [file]. A file that is missing or unreadable
  /// reads as nothing having been decided yet.
  static Future<ToolbarPins> open(File file) async {
    var pinned = <String>[];
    var known = <String>{};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        List<String> strings(Object? value) =>
            value is List ? value.whereType<String>().toList() : [];
        pinned = strings(json['pinned']).toSet().toList();
        known = {...strings(json['known']), ...pinned};
      }
    } on FileSystemException {
      // Nothing saved yet.
    } on FormatException {
      // Not ours to understand; it is replaced at the next change.
    }
    return ToolbarPins._(file, pinned, known);
  }

  final File _file;
  final List<String> _pinned;

  /// The extensions that have had their first placement, so that what the user
  /// chose since is not put back to what the extension asked for.
  final Set<String> _known;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void> _saving = Future<void>.value();

  Stream<void> get changes => _changes.stream;

  /// The uuids of the pinned extensions, in the order of their buttons.
  List<String> get pinned => List.unmodifiable(_pinned);

  bool isPinned(String uuid) => _pinned.contains(uuid);

  /// Gives an extension seen for the first time its place: on the toolbar only
  /// if its manifest asked for that with [onToolbar].
  Future<void> introduce(String uuid, {required bool onToolbar}) {
    if (!_known.add(uuid)) return _saving;
    if (onToolbar) _pinned.add(uuid);
    return _changed();
  }

  /// Pins or unpins. A newly pinned button goes at the end.
  Future<void> setPinned(String uuid, {required bool pinned}) {
    _known.add(uuid);
    if (pinned == isPinned(uuid)) return _saving;
    pinned ? _pinned.add(uuid) : _pinned.remove(uuid);
    return _changed();
  }

  /// Forgets an extension that was uninstalled, so that installing it again
  /// starts over.
  Future<void> forget(String uuid) {
    final known = _known.remove(uuid);
    final pinned = _pinned.remove(uuid);
    return known || pinned ? _changed() : _saving;
  }

  Future<void> _changed() {
    if (!_changes.isClosed) _changes.add(null);
    final text = jsonEncode({'pinned': _pinned, 'known': _known.toList()});
    // One write at a time, each of a whole file that replaces the old one.
    return _saving = _saving
        .then((_) async {
          await _file.parent.create(recursive: true);
          final temporary = File('${_file.path}.tmp');
          await temporary.writeAsString(text, flush: true);
          await temporary.rename(_file.path);
        })
        .catchError((_) {
          // A choice that cannot be saved still holds until the app quits.
        });
  }

  Future<void> dispose() async {
    await _saving;
    await _changes.close();
  }
}
