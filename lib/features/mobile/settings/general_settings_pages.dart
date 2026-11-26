import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';

/// The zooms a page can start at, as the engine's `defaultZoomLevelFactor`.
const List<double> _zoomLevels = [
  0.5,
  0.67,
  0.75,
  0.8,
  0.9,
  1.0,
  1.1,
  1.25,
  1.5,
  1.75,
  2.0,
];

void _apply(WidgetRef ref, Map<String, Object?> changes) {
  if (ref.read(settingsProvider.notifier).apply(changes)) return;
  debugPrint('The engine refused a settings change: $changes');
}

/// Whether the address bar is at the top or the bottom, shown as pictures.
class AddressBarSettingsPage extends ConsumerWidget {
  const AddressBarSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      mobilePreferencesProvider.select((value) => value.addressBar),
    );
    void choose(AddressBarPosition next) =>
        ref.read(mobilePreferencesProvider.notifier).setAddressBar(next);

    return SettingsScreen(
      title: 'Address bar',
      children: [
        SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final option in AddressBarPosition.values)
                    _PhonePicture(
                      position: option,
                      selected: option == position,
                      onTap: () => choose(option),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsChoiceRow(
              title: 'Top',
              selected: position == AddressBarPosition.top,
              onTap: () => choose(AddressBarPosition.top),
            ),
            SettingsChoiceRow(
              title: 'Bottom',
              selected: position == AddressBarPosition.bottom,
              onTap: () => choose(AddressBarPosition.bottom),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhonePicture extends StatelessWidget {
  const _PhonePicture({
    required this.position,
    required this.selected,
    required this.onTap,
  });

  final AddressBarPosition position;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final bar = Padding(
      padding: const EdgeInsets.all(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 18,
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.containerHigh,
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
    Widget line(double width) => Container(
      width: width,
      height: 7,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.containerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: position == AddressBarPosition.top ? 'Top' : 'Bottom',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 104,
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
              width: selected ? 3 : 1.5,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (position == AddressBarPosition.top) bar,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [line(70), line(60), line(66), line(44)],
                ),
              ),
              if (position == AddressBarPosition.bottom) bar,
            ],
          ),
        ),
      ),
    );
  }
}

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    const schemes = [
      ('system', 'System default'),
      ('light', 'Light'),
      ('dark', 'Dark'),
    ];
    return SettingsScreen(
      title: 'Appearance',
      children: [
        SettingsGroup(
          title: 'Theme',
          children: [
            for (final (value, label) in schemes)
              SettingsChoiceRow(
                title: label,
                selected: settings.interfaceTheme == value,
                onTap: () => _apply(ref, {
                  'appearance': {'interfaceTheme': value},
                }),
              ),
          ],
        ),
        SettingsGroup(
          title: 'What websites are told',
          children: [
            for (final (value, label) in schemes)
              SettingsChoiceRow(
                title: label,
                selected: settings.websiteColorScheme == value,
                onTap: () => _apply(ref, {
                  'appearance': {'websiteColorScheme': value},
                }),
              ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              title: 'Darken websites',
              subtitle: 'Draw pages with no dark theme of their own in one',
              value: settings.forceDark,
              onChanged: (value) => _apply(ref, {
                'content': {'enableForceDark': value},
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class AccessibilitySettingsPage extends ConsumerStatefulWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  ConsumerState<AccessibilitySettingsPage> createState() =>
      _AccessibilitySettingsPageState();
}

class _AccessibilitySettingsPageState
    extends ConsumerState<AccessibilitySettingsPage> {
  /// Where the slider is while it is being dragged.
  int? _dragging;

  static int _nearest(double zoom) {
    var best = 0;
    for (var i = 1; i < _zoomLevels.length; i++) {
      if ((_zoomLevels[i] - zoom).abs() < (_zoomLevels[best] - zoom).abs()) {
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final stored = ref.watch(
      settingsProvider.select((s) => s.defaultZoomLevelFactor),
    );
    final index = _dragging ?? _nearest(stored);
    final zoom = _dragging == null ? stored : _zoomLevels[index];

    return SettingsScreen(
      title: 'Accessibility',
      children: [
        SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Page zoom',
                          style: TextStyle(fontSize: 16, color: colors.text),
                        ),
                      ),
                      Text(
                        '${(zoom * 100).round()}%',
                        style: TextStyle(fontSize: 14, color: colors.accent),
                      ),
                    ],
                  ),
                  Slider(
                    value: index.toDouble(),
                    max: (_zoomLevels.length - 1).toDouble(),
                    divisions: _zoomLevels.length - 1,
                    label: '${(zoom * 100).round()}%',
                    onChanged: (value) =>
                        setState(() => _dragging = value.round()),
                    // The engine saves each change, so it gets only the last.
                    onChangeEnd: (value) {
                      _apply(ref, {
                        'content': {
                          'defaultZoomLevelFactor': _zoomLevels[value.round()],
                        },
                      });
                      setState(() => _dragging = null);
                    },
                  ),
                  SizedBox(
                    height: 96,
                    child: ClipRect(
                      child: Center(
                        child: Text(
                          'Text on pages looks like this.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16 * zoom,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class SiteSettingsPage extends ConsumerWidget {
  const SiteSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(settingsProvider.select((s) => s.autoplayPolicy));
    return SettingsScreen(
      title: 'Site settings',
      children: [
        SettingsGroup(
          title: 'Autoplay',
          children: [
            for (final (value, label) in const [
              ('allow-audio-and-video', 'Allow audio and video'),
              ('block-audio', 'Block audio'),
              ('block-audio-and-video', 'Block audio and video'),
            ])
              SettingsChoiceRow(
                title: label,
                selected: policy == value,
                onTap: () => _apply(ref, {
                  'autoplay': {'policy': value},
                }),
              ),
          ],
        ),
      ],
    );
  }
}

/// The engine's own list of options, shown without knowing any of them.
class EngineSettingsPage extends ConsumerWidget {
  const EngineSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final definitions = ref.watch(configVariableDefinitionsProvider);
    return SettingsScreen(
      title: 'Engine options',
      children: [
        if (definitions.isEmpty)
          const SettingsGroup(
            children: [SettingsRow(title: 'The engine offers none.')],
          )
        else
          SettingsGroup(
            children: [
              for (final definition in definitions)
                _row(context, ref, definition, settings.configVariable),
            ],
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    LadybirdConfigVariableDefinition definition,
    dynamic Function(String name) valueOf,
  ) {
    void set(Object? value) {
      final notifier = ref.read(settingsProvider.notifier);
      if (notifier.setConfigVariable(definition.name, value)) return;
      debugPrint('The engine refused the config variable ${definition.name}.');
    }

    final value = valueOf(definition.name);
    if (value is bool) {
      return SettingsSwitchRow(
        title: definition.title,
        subtitle: definition.description,
        value: value,
        onChanged: set,
      );
    }
    return SettingsRow(
      title: definition.title,
      subtitle: definition.description,
      trailing: Text(value == null ? '—' : '$value'),
      onTap: value is! num
          ? null
          : () async {
              final entered = await showDialog<String>(
                context: context,
                builder: (context) =>
                    _NumberDialog(title: definition.title, value: value),
              );
              final parsed = num.tryParse(entered?.trim() ?? '');
              if (parsed == null || !context.mounted) return;
              set(value is int ? parsed.toInt() : parsed.toDouble());
            },
    );
  }
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.value});

  final String title;
  final num value;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return SettingsScreen(
      title: 'About Rubisco',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Image.asset(
                'browser-logo.png',
                width: 112,
                height: 112,
                cacheWidth: 336,
              ),
              const SizedBox(height: 12),
              Text(
                'Rubisco Browser',
                style: TextStyle(fontSize: 22, color: colors.text),
              ),
            ],
          ),
        ),
        const SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.bug_report_outlined,
              title: 'Engine',
              subtitle: 'Built on the Ladybird engine',
            ),
          ],
        ),
      ],
    );
  }
}
