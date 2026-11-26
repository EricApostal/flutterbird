import 'package:flutter/widgets.dart';

import '../model/session.dart';
import '../model/settings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'tools.dart';

/// The toolbox's options, as Firefox's Settings panel lays them out.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.session});

  final ToolboxSession session;

  static const List<(String, String)> _shortcuts = [
    ('Toggle the developer tools', '⌥⌘I  or  F12'),
    ('Web Console', '⌥⌘K'),
    ('Pick an element from the page', '⌥⌘C  or  ⇧⌘C'),
    ('Debugger', '⌥⌘Z'),
    ('Network Monitor', '⌥⌘E'),
    ('Style Editor', '⇧F7'),
    ('Storage Inspector', '⇧F9'),
    ('Responsive Design Mode', '⌥⌘M'),
    ('Toggle the split console', 'Esc'),
    ('Next / previous tool', '⌘]  /  ⌘['),
    ('Settings', 'F1'),
    ('Resume / pause', 'F8'),
    ('Step over / in / out', 'F10  /  F11  /  ⇧F11'),
    ('Go to file (Debugger)', '⌘P'),
    ('Search (in a tool)', '⌘F'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = session.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final colors = context.dt;
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: context.uiStyle(color: colors.textStrong, size: 14, weight: FontWeight.w600)),
        );
        Widget check(String label, bool value, ValueChanged<bool>? onChanged, {String tooltip = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: DtCheckbox(label: label, value: value, onChanged: onChanged, tooltip: tooltip),
        );
        Widget flag(String label, String key, {bool fallback = false}) =>
            check(label, settings.flag(key, fallback), (on) => settings.set(key, on));

        final columns = [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Default Developer Tools'),
              for (final tool in devToolsTools)
                check(
                  tool.label,
                  settings.isPanelEnabled(tool.id),
                  tool.id == 'inspector' || tool.id == 'console' ? null : (on) => settings.setPanelEnabled(tool.id, on),
                ),
              heading('Themes'),
              for (final (choice, label) in const [
                (DevToolsThemeChoice.auto, 'Auto'),
                (DevToolsThemeChoice.light, 'Light'),
                (DevToolsThemeChoice.dark, 'Dark'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: DtCheckbox(radio: true, label: label, value: settings.theme == choice, onChanged: (_) => settings.theme = choice),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Inspector'),
              check('Show Browser Styles', session.inspector.showBrowserStyles, session.inspector.setShowBrowserStyles),
              flag('Three-pane inspector', 'inspector.threePane'),
              heading('Web Console'),
              flag('Persist logs', 'console.persist'),
              flag('Show timestamps', 'console.timestamps'),
              flag('Group similar messages', 'console.groupSimilar', fallback: true),
              flag('Enable autocompletion', 'console.autocomplete', fallback: true),
              heading('Network Monitor'),
              flag('Persist logs', 'network.persist'),
              heading('JavaScript Debugger'),
              check('Pause on debugger statement', session.debugger.pauseOnDebuggerStatement, (on) => session.debugger.setOption('pauseOnDebuggerStatement', on)),
              check('Pause on exceptions', session.debugger.pauseOnExceptions, (on) => session.debugger.setOption('pauseOnExceptions', on)),
              heading('Not supported by the engine'),
              check('Disable HTTP Cache', false, null, tooltip: 'The engine’s DevTools server does not offer this'),
              check('Disable JavaScript', false, null, tooltip: 'The engine’s DevTools server does not offer this'),
              check('Simulate print media', false, null, tooltip: 'The engine’s DevTools server does not offer this'),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Keyboard Shortcuts'),
              for (final (action, keys) in _shortcuts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(action, style: context.uiStyle())),
                      const SizedBox(width: 10),
                      Text(keys, style: context.uiStyle(color: colors.textStrong)),
                    ],
                  ),
                ),
            ],
          ),
        ];

        return ColoredBox(
          color: colors.body,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 700
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (index, column) in columns.indexed) ...[
                          if (index > 0) const SizedBox(width: 40),
                          Expanded(child: column),
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
