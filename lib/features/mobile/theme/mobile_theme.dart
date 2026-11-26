import 'package:material_ui/material_ui.dart';

/// The colours of the phone interface, which are those of Chrome on Android
/// without a wallpaper's tint.
@immutable
class MobileColors extends ThemeExtension<MobileColors> {
  const MobileColors({
    required this.surface,
    required this.field,
    required this.container,
    required this.containerHigh,
    required this.menu,
    required this.settingsBackground,
    required this.settingsTile,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.divider,
    required this.link,
    required this.danger,
  });

  /// Toolbars and the new tab page.
  final Color surface;

  /// The address bar and search boxes.
  final Color field;

  /// Cards and icon backgrounds.
  final Color container;

  /// Tab cards.
  final Color containerHigh;
  final Color menu;
  final Color settingsBackground;
  final Color settingsTile;
  final Color text;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color divider;
  final Color link;
  final Color danger;

  static const MobileColors light = MobileColors(
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFE9EEF6),
    container: Color(0xFFF0F4F9),
    containerHigh: Color(0xFFE1E7F0),
    menu: Color(0xFFF8FAFD),
    settingsBackground: Color(0xFFEEF2F8),
    settingsTile: Color(0xFFFFFFFF),
    text: Color(0xFF1F1F1F),
    textSecondary: Color(0xFF5E6064),
    accent: Color(0xFF0B57D0),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFD3E3FD),
    onAccentContainer: Color(0xFF041E49),
    divider: Color(0xFFDDE1E6),
    link: Color(0xFF0B57D0),
    danger: Color(0xFFB3261E),
  );

  static const MobileColors dark = MobileColors(
    surface: Color(0xFF1F1F1F),
    field: Color(0xFF2D2F31),
    container: Color(0xFF28292B),
    containerHigh: Color(0xFF37393B),
    menu: Color(0xFF2B2C2F),
    settingsBackground: Color(0xFF141416),
    settingsTile: Color(0xFF242528),
    text: Color(0xFFE3E3E3),
    textSecondary: Color(0xFFABAFB3),
    accent: Color(0xFFA8C7FA),
    onAccent: Color(0xFF062E6F),
    accentContainer: Color(0xFF0842A0),
    onAccentContainer: Color(0xFFD3E3FD),
    divider: Color(0xFF3C4043),
    link: Color(0xFFA8C7FA),
    danger: Color(0xFFF2B8B5),
  );

  @override
  MobileColors copyWith() => this;

  @override
  MobileColors lerp(MobileColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MobileColors(
      surface: mix(surface, other.surface),
      field: mix(field, other.field),
      container: mix(container, other.container),
      containerHigh: mix(containerHigh, other.containerHigh),
      menu: mix(menu, other.menu),
      settingsBackground: mix(settingsBackground, other.settingsBackground),
      settingsTile: mix(settingsTile, other.settingsTile),
      text: mix(text, other.text),
      textSecondary: mix(textSecondary, other.textSecondary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentContainer: mix(accentContainer, other.accentContainer),
      onAccentContainer: mix(onAccentContainer, other.onAccentContainer),
      divider: mix(divider, other.divider),
      link: mix(link, other.link),
      danger: mix(danger, other.danger),
    );
  }
}

extension MobileThemeContext on BuildContext {
  MobileColors get mobile =>
      Theme.of(this).extension<MobileColors>() ?? MobileColors.light;
}

/// The theme of the phone interface, light or dark.
ThemeData mobileTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? MobileColors.dark
      : MobileColors.light;
  final scheme =
      ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: MobileColors.light.accent,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        primaryContainer: colors.accentContainer,
        onPrimaryContainer: colors.onAccentContainer,
        secondaryContainer: colors.accentContainer,
        onSecondaryContainer: colors.onAccentContainer,
        surface: colors.surface,
        onSurface: colors.text,
        onSurfaceVariant: colors.textSecondary,
        surfaceContainerLow: colors.menu,
        surfaceContainer: colors.container,
        surfaceContainerHigh: colors.menu,
        surfaceContainerHighest: colors.containerHigh,
        outlineVariant: colors.divider,
        error: colors.danger,
      );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);

  return base.copyWith(
    extensions: [colors],
    scaffoldBackgroundColor: colors.surface,
    dividerTheme: DividerThemeData(
      color: colors.divider,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: colors.text, size: 24),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.menu,
      modalBackgroundColor: colors.menu,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.menu,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: 0.35),
      selectionHandleColor: colors.accent,
    ),
  );
}
