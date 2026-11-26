import 'dart:convert';
import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which edge of the screen the address bar and its buttons are on.
enum AddressBarPosition { top, bottom }

/// What the user chose about the phone interface itself.
class MobilePreferences {
  const MobilePreferences({this.addressBar = AddressBarPosition.bottom});

  factory MobilePreferences.fromJson(Object? json) {
    if (json is! Map) return const MobilePreferences();
    return MobilePreferences(
      addressBar: json['addressBar'] == 'top'
          ? AddressBarPosition.top
          : AddressBarPosition.bottom,
    );
  }

  final AddressBarPosition addressBar;

  Map<String, Object?> toJson() => {'addressBar': addressBar.name};
}

/// [MobilePreferences], kept in the engine's profile.
class MobilePreferencesController extends Notifier<MobilePreferences> {
  File? _file;

  @override
  MobilePreferences build() {
    // Read at once, so that the first frame already has the bar where it was
    // left. The engine is up by now: it started with the first tab.
    final tabs = ref.read(browserTabControllerProvider);
    final directory = tabs.isEmpty
        ? null
        : tabs.first.getProfileConfigDirectory();
    if (directory == null) return const MobilePreferences();

    final file = _file = File('$directory/MobileUI.json');
    try {
      if (file.existsSync()) {
        return MobilePreferences.fromJson(jsonDecode(file.readAsStringSync()));
      }
    } on FormatException catch (error) {
      debugPrint('Unable to parse the interface settings: $error');
    } on FileSystemException catch (error) {
      debugPrint('Unable to read the interface settings: $error');
    }
    return const MobilePreferences();
  }

  void setAddressBar(AddressBarPosition position) =>
      _save(MobilePreferences(addressBar: position));

  void _save(MobilePreferences preferences) {
    state = preferences;
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final temporary = File('${file.path}.tmp')
        ..writeAsStringSync(jsonEncode(preferences.toJson()), flush: true);
      temporary.renameSync(file.path);
    } on FileSystemException catch (error) {
      debugPrint('Unable to save the interface settings: $error');
    }
  }
}

final mobilePreferencesProvider =
    NotifierProvider<MobilePreferencesController, MobilePreferences>(
      MobilePreferencesController.new,
    );
