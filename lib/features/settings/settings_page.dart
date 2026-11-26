import 'dart:io';

import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:rubisco_browser/features/settings/engine_settings.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';

const double _sidebarWidth = 208;
const double _contentWidth = 720;

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

enum _Section {
  appearance,
  search,
  browsing,
  content,
  privacy,
  advanced;

  String get title => switch (this) {
    _Section.appearance => 'Appearance',
    _Section.search => 'Search',
    _Section.browsing => 'Browsing',
    _Section.content => 'Content',
    _Section.privacy => 'Privacy',
    _Section.advanced => 'Advanced',
  };

  String get description => switch (this) {
    _Section.appearance =>
      "How the browser's own interface and the pages it shows are drawn.",
    _Section.search => 'What the address bar searches with.',
    _Section.browsing => 'How pages behave while you read them.',
    _Section.content => 'How pages are rendered and scaled.',
    _Section.privacy => 'What the browser shares, and what it blocks.',
    _Section.advanced => 'Engine options that rarely need changing.',
  };
}

/// The browser's settings, drawn over the engine's own settings page at
/// `about:settings`, as the new tab page is drawn over its blank one.
///
/// Every value comes from the engine and every change goes back to it, so the
/// two never hold different ideas of what is set.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final FocusNode _pageFocus = FocusNode(debugLabel: 'Settings');
  final TextEditingController _customName = TextEditingController();
  final TextEditingController _customUrl = TextEditingController();

  _Section _section = _Section.appearance;
  String? _customError;

  @override
  void initState() {
    super.initState();
    // The engine may have changed them since this snapshot was taken, such as
    // when its own first-run defaults were written.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(settingsProvider.notifier).reload();
    });
  }

  @override
  void dispose() {
    _pageFocus.dispose();
    _customName.dispose();
    _customUrl.dispose();
    super.dispose();
  }

  void _apply(Map<String, Object?> changes) {
    if (ref.read(settingsProvider.notifier).apply(changes)) return;
    debugPrint('The engine refused a settings change: $changes');
  }

  void _setConfigVariable(String name, Object? value) {
    if (ref.read(settingsProvider.notifier).setConfigVariable(name, value)) {
      return;
    }
    debugPrint('The engine refused the config variable $name.');
  }

  void _addCustomEngine() {
    try {
      LadybirdController.addNewSearchEngine(_customName.text, _customUrl.text);
    } on ArgumentError catch (error) {
      setState(() => _customError = error.message?.toString());
      return;
    }
    _customName.clear();
    _customUrl.clear();
    setState(() => _customError = null);
    ref.read(settingsProvider.notifier).reload();
  }

  void _removeCustomEngine(String name) {
    if (!LadybirdController.removeCustomSearchEngine(name)) {
      debugPrint('The engine refused to remove the search engine $name.');
      return;
    }
    ref.read(settingsProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final settings = ref.watch(settingsProvider);

    // Opaque, so that nothing reaches the page underneath, and focusable, so
    // that the keyboard is not left with the engine's hidden settings page.
    return ColoredBox(
      color: colors.toolbar,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pageFocus.requestFocus(),
        child: Focus(
          focusNode: _pageFocus,
          autofocus: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: _sidebarWidth, child: _sidebar()),
              const BirdSeparator(vertical: true),
              Expanded(
                child: settings.isLoaded
                    ? _content(settings)
                    : _Unavailable(
                        onRetry: () =>
                            ref.read(settingsProvider.notifier).reload(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 14),
            child: Text(
              'Settings',
              style: context.birdText(
                size: BirdTextSize.title,
                weight: FontWeight.w600,
              ),
            ),
          ),
          for (final section in _Section.values)
            _NavItem(
              label: section.title,
              selected: section == _section,
              onPressed: () => setState(() => _section = section),
            ),
        ],
      ),
    );
  }

  Widget _content(EngineSettings settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _section.title,
                style: context.birdText(
                  size: 22,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _section.description,
                style: context.birdText(
                  color: context.bird.textSecondary,
                  size: BirdTextSize.small,
                ),
              ),
              const SizedBox(height: 18),
              ...switch (_section) {
                _Section.appearance => _appearance(settings),
                _Section.search => _search(settings),
                _Section.browsing => _browsing(settings),
                _Section.content => _contentSettings(settings),
                _Section.privacy => _privacy(settings),
                _Section.advanced => _advanced(settings),
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _appearance(EngineSettings settings) => [
    _SectionCard(
      children: [
        _SettingRow(
          title: 'Interface theme',
          description: "The browser's own tabs, toolbars and menus.",
          control: BirdSelect<String>(
            value: settings.interfaceTheme,
            semanticLabel: 'Interface theme',
            options: const [
              BirdOption('system', 'System'),
              BirdOption('light', 'Light'),
              BirdOption('dark', 'Dark'),
            ],
            onChanged: (value) =>
                _apply({'appearance': {'interfaceTheme': value}}),
          ),
        ),
        _SettingRow(
          title: 'Website color scheme',
          description:
              'Whether pages are told the system is in light or dark mode.',
          control: BirdSelect<String>(
            value: settings.websiteColorScheme,
            semanticLabel: 'Website color scheme',
            options: const [
              BirdOption('system', 'System'),
              BirdOption('light', 'Light'),
              BirdOption('dark', 'Dark'),
            ],
            onChanged: (value) =>
                _apply({'appearance': {'websiteColorScheme': value}}),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _search(EngineSettings settings) {
    final engines = ref.watch(searchEnginesProvider);
    final custom = settings.customSearchEngines;
    return [
      _SectionCard(
        children: [
          _SettingRow(
            title: 'Search engine',
            description:
                'What the address bar searches with when what you type is '
                'not an address.',
            control: BirdSelect<String>(
              value: settings.searchEngineName ?? '',
              semanticLabel: 'Search engine',
              options: [
                const BirdOption('', 'Default'),
                for (final engine in engines)
                  BirdOption(engine.name, engine.name),
              ],
              onChanged: (name) =>
                  _apply({'searchEngine': {'engine': name.isEmpty ? null : name}}),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _SectionCard(
        children: [
          for (final engine in custom)
            _SettingRow(
              title: engine.name,
              description: engine.queryUrl,
              control: BirdButton(
                'Remove',
                kind: BirdButtonKind.ghost,
                small: true,
                onPressed: () => _removeCustomEngine(engine.name),
              ),
            ),
          _SettingRow(
            title: 'Add a search engine',
            description:
                'The URL takes %s where the search text goes, e.g. '
                '"https://example.com/search?q=%s".',
            stacked: true,
            control: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: BirdTextField(
                        controller: _customName,
                        placeholder: 'Name',
                        semanticLabel: 'New search engine name',
                        onSubmitted: (_) => _addCustomEngine(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: BirdTextField(
                        controller: _customUrl,
                        placeholder: 'Search URL',
                        semanticLabel: 'New search engine URL',
                        onSubmitted: (_) => _addCustomEngine(),
                      ),
                    ),
                  ],
                ),
                if (_customError case final error?) ...[
                  const SizedBox(height: 6),
                  Text(
                    error,
                    style: context.birdText(
                      color: context.bird.danger,
                      size: BirdTextSize.small,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    BirdButton.primary(
                      'Add engine',
                      small: true,
                      onPressed: _addCustomEngine,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _browsing(EngineSettings settings) => [
    _SectionCard(
      children: [
        _SettingRow(
          title: 'Autoplay',
          description: 'What video and audio may start on their own.',
          control: BirdSelect<String>(
            value: settings.autoplayPolicy,
            semanticLabel: 'Autoplay',
            options: const [
              BirdOption('allow-audio-and-video', 'Allow audio and video'),
              BirdOption('block-audio', 'Block audio'),
              BirdOption('block-audio-and-video', 'Block audio and video'),
            ],
            onChanged: (value) => _apply({
              'autoplay': {'policy': value},
            }),
          ),
        ),
        _SettingRow(
          title: 'Scroll with the middle mouse button',
          description: 'Start scrolling a page by clicking its middle.',
          control: BirdSwitch(
            value: settings.autoscroll,
            semanticLabel: 'Scroll with the middle mouse button',
            onChanged: (value) =>
                _apply({'browsingBehavior': {'enableAutoscroll': value}}),
          ),
        ),
        if (Platform.isLinux)
          _SettingRow(
            title: 'Paste with the middle mouse button',
            description: 'Paste the primary selection where you click.',
            control: BirdSwitch(
              value: settings.primaryPaste,
              semanticLabel: 'Paste with the middle mouse button',
              onChanged: (value) =>
                  _apply({'browsingBehavior': {'enablePrimaryPaste': value}}),
            ),
          ),
      ],
    ),
  ];

  List<Widget> _contentSettings(EngineSettings settings) {
    final zoom = settings.defaultZoomLevelFactor;
    return [
      _SectionCard(
        children: [
          _SettingRow(
            title: 'Page zoom',
            description: 'The zoom every page starts at.',
            control: BirdSelect<double>(
              value: zoom,
              semanticLabel: 'Page zoom',
              options: [
                for (final level in _zoomLevels)
                  BirdOption(level, '${(level * 100).round()}%'),
                if (!_zoomLevels.contains(zoom))
                  BirdOption(zoom, '${(zoom * 100).round()}%'),
              ],
              onChanged: (value) =>
                  _apply({'content': {'defaultZoomLevelFactor': value}}),
            ),
          ),
          _SettingRow(
            title: 'Force dark mode',
            description:
                'Draw pages that have no dark theme of their own in one.',
            control: BirdSwitch(
              value: settings.forceDark,
              semanticLabel: 'Force dark mode',
              onChanged: (value) =>
                  _apply({'content': {'enableForceDark': value}}),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _privacy(EngineSettings settings) => [
    _SectionCard(
      children: [
        _SettingRow(
          title: 'Global Privacy Control',
          description:
              'Ask every site not to sell or share what you do on it.',
          control: BirdSwitch(
            value: settings.globalPrivacyControl,
            semanticLabel: 'Global Privacy Control',
            onChanged: (value) => _apply({'globalPrivacyControl': value}),
          ),
        ),
        _SettingRow(
          title: 'Content blocking',
          description: 'Block ads, trackers and other unwanted requests.',
          control: BirdSwitch(
            value: settings.contentBlockerEnabled,
            semanticLabel: 'Content blocking',
            onChanged: (value) =>
                _apply({'contentBlockers': {'enabled': value}}),
          ),
        ),
        _SettingRow(
          title: 'Background networking',
          description:
              'Let the browser fetch things while you are not on a page, '
              'such as newer filter lists.',
          control: BirdSwitch(
            value: settings.backgroundNetworkingEnabled,
            semanticLabel: 'Background networking',
            onChanged: (value) =>
                _apply({'backgroundNetworking': {'enabled': value}}),
          ),
        ),
        _SettingRow(
          title: 'Update filter lists automatically',
          description:
              'Download newer versions of the content blocker lists while '
              'the browser runs.',
          control: BirdSwitch(
            value: settings.filterListUpdatesEnabled,
            semanticLabel: 'Update filter lists automatically',
            onChanged: (value) => _apply({
              'backgroundNetworking': {
                'features': {'contentBlockerSubscriptionUpdates': value},
              },
            }),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _advanced(EngineSettings settings) => [
    _SectionCard(
      children: [
        for (final definition in ref.watch(configVariableDefinitionsProvider))
          _configRow(definition, settings),
      ],
    ),
  ];

  Widget _configRow(
    LadybirdConfigVariableDefinition definition,
    EngineSettings settings,
  ) {
    final value = settings.configVariable(definition.name);
    final control = switch (value) {
      bool value => BirdSwitch(
        value: value,
        semanticLabel: definition.title,
        onChanged: (next) => _setConfigVariable(definition.name, next),
      ),
      num value => SizedBox(
        width: 140,
        child: _NumberSetting(
          value: value,
          semanticLabel: definition.title,
          onChanged: (next) => _setConfigVariable(definition.name, next),
        ),
      ),
      null => const Text('—'),
      _ => Text(
        '$value',
        style: context.birdText(color: context.bird.textSecondary),
      ),
    };

    return _SettingRow(
      title: definition.title,
      description: definition.description,
      control: control,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return BirdPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => BirdFocusRing(
        visible: state.focused,
        child: Container(
          height: 30,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected
                ? colors.controlActive
                : (state.hovered ? colors.hover : null),
            borderRadius: BorderRadius.circular(BirdRadius.control),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.birdText(
              weight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows of settings on one surface, divided by soft lines.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(BirdRadius.dialog),
        border: Border.all(color: colors.panelBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const BirdSeparator(),
            child,
          ],
        ],
      ),
    );
  }
}

/// What a setting is called and does, with the control that changes it.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.control,
    this.description,
    this.stacked = false,
  });

  final String title;
  final String? description;
  final Widget control;

  /// Puts the control under the words, for one that needs the width.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: context.birdText()),
        if (description case final description?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              description,
              style: context.birdText(
                color: context.bird.textSecondary,
                size: BirdTextSize.small,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labels, const SizedBox(height: 10), control],
            )
          : Row(
              children: [
                Expanded(child: labels),
                const SizedBox(width: 16),
                control,
              ],
            ),
    );
  }
}

/// A number typed in, which is applied when it is done being typed.
class _NumberSetting extends StatefulWidget {
  const _NumberSetting({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final String? semanticLabel;

  @override
  State<_NumberSetting> createState() => _NumberSettingState();
}

class _NumberSettingState extends State<_NumberSetting> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _NumberSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  static String _format(num value) => value is int
      ? value.toString()
      : (value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString());

  void _commit() {
    final parsed = num.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }

    final value = widget.value is int ? parsed.toInt() : parsed.toDouble();
    if (value == widget.value) {
      _controller.text = _format(widget.value);
      return;
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return BirdTextField(
      controller: _controller,
      focusNode: _focus,
      semanticLabel: widget.semanticLabel,
      onSubmitted: (_) => _commit(),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The engine is not ready to show its settings.',
            style: context.birdText(color: context.bird.textSecondary),
          ),
          const SizedBox(height: 12),
          BirdButton('Try again', small: true, onPressed: onRetry),
        ],
      ),
    );
  }
}
