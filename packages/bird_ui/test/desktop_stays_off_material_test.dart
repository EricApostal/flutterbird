// The desktop interface is drawn with this library. This keeps Material from
// finding its way back in: an import of it is for Android's files, and for the
// few that serve both.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files of the app that may import Material, and why.
const allowed = {
  // Android's own interface.
  'features/browser/components/mobile_browser_layout.dart',
  'features/browser/components/mobile_omnibox_bar.dart',
  'features/browser/components/mobile_tab_card.dart',
  'features/browser/components/mobile_tab_switcher.dart',
  'features/theme/app_theme.dart',
  'features/theme/base.dart',
  // Serve both, and take Material's way only under Android's app.
  'main.dart',
  'features/browser/components/browser_context_menu.dart',
  'features/browser/components/browser_window.dart',
  'features/browser/screens/loading.dart',
};

final _import = RegExp(r'''^import\s+['"]package:(material_ui/|cupertino_ui/|flutter/material|flutter/cupertino)''', multiLine: true);

void main() {
  final app = Directory('../../lib');

  test('only Android and what it shares import Material', () {
    final offenders = <String>[];
    for (final file in app.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.path.substring(app.path.length + 1);
      final matches = _import.allMatches(file.readAsStringSync());
      if (matches.isEmpty) continue;
      // The framework's own Material is on its way out, for every file.
      if (matches.any((match) => match.group(1)!.startsWith('flutter/'))) {
        offenders.add('$path imports the framework\'s Material: use package:material_ui');
      } else if (!allowed.contains(path)) {
        offenders.add('$path is a desktop file: use package:bird_ui');
      }
    }
    expect(offenders, isEmpty);
  }, skip: app.existsSync() ? false : 'not inside the app');
}
