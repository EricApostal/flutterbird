import 'dart:convert';
import 'dart:io';

import 'package:bird_session/bird_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the user chose to have on the new tab page, kept in the profile.
class NewTabSettingsController extends Notifier<NewTabSettings> {
  File? _file;

  @override
  NewTabSettings build() => const NewTabSettings();

  /// Reads what was kept in [directory], the engine's profile, the first time
  /// there is one to read from.
  void load(String? directory) {
    if (_file != null || directory == null) return;
    final file = _file = File('$directory/NewTab.json');
    try {
      if (file.existsSync()) {
        state = NewTabSettings.fromJson(jsonDecode(file.readAsStringSync()));
      }
    } on FormatException catch (error) {
      debugPrint('Unable to parse the new tab page settings: $error');
    } on FileSystemException catch (error) {
      debugPrint('Unable to read the new tab page settings: $error');
    }
  }

  void change(NewTabSettings settings) {
    state = settings;
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final temporary = File('${file.path}.tmp')
        ..writeAsStringSync(jsonEncode(settings.toJson()), flush: true);
      temporary.renameSync(file.path);
    } on FileSystemException catch (error) {
      debugPrint('Unable to save the new tab page settings: $error');
    }
  }
}

final newTabSettingsProvider =
    NotifierProvider<NewTabSettingsController, NewTabSettings>(
      NewTabSettingsController.new,
    );
