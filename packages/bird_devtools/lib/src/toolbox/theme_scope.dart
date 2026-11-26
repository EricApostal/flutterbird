import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// What the tools' widgets need around them: their colours, their scrolling,
/// the platform's editing keys, and somewhere to put menus.
class DevToolsScope extends StatefulWidget {
  const DevToolsScope({super.key, required this.settings, required this.child, this.autoBrightness});

  final DevToolsSettings settings;

  /// What the "Auto" theme follows, where it is not the system's setting.
  final Brightness? autoBrightness;
  final Widget child;

  @override
  State<DevToolsScope> createState() => _DevToolsScopeState();
}

class _DevToolsScopeState extends State<DevToolsScope> {
  OverlayEntry? _entry;

  @override
  void didUpdateWidget(DevToolsScope old) {
    super.didUpdateWidget(old);
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      final brightness = switch (widget.settings.theme) {
        DevToolsThemeChoice.light => Brightness.light,
        DevToolsThemeChoice.dark => Brightness.dark,
        DevToolsThemeChoice.auto => widget.autoBrightness ?? MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
      };
      final colors = brightness == Brightness.dark ? DtColors.dark : DtColors.light;
      Widget content = DtTheme(
        colors: colors,
        child: BirdTheme(
          colors: colors.bird,
          child: BirdMenuTheme(
            compact: true,
            child: DefaultTextEditingShortcuts(
              child: ScrollConfiguration(
                behavior: const DtScrollBehavior(),
                child: DefaultSelectionStyle(
                  cursorColor: colors.textStrong,
                  selectionColor: colors.accent.withValues(alpha: 0.35),
                  child: Builder(builder: (context) => widget.child),
                ),
              ),
            ),
          ),
        ),
      );
      if (Overlay.maybeOf(context) != null) return content;
      // A window with nothing above the tools in it needs an overlay of its
      // own for menus and tooltips.
      final held = content;
      _latest = held;
      _entry ??= OverlayEntry(builder: (context) => _latest!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entry?.markNeedsBuild();
      });
      return Directionality(textDirection: TextDirection.ltr, child: Overlay(initialEntries: [_entry!]));
    },
  );

  Widget? _latest;
}
