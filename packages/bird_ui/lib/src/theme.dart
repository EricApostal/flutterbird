import 'package:flutter/widgets.dart';

/// The two colours of Rubisco's mark, which the palettes are made from: the
/// blue of its ring, and the blue-black behind it, which tints the greys.
abstract final class BirdBrand {
  static const Color blue = Color(0xFF277AFF);
  static const Color ink = Color(0xFF11141D);
}

/// The colours of the browser's own interface.
@immutable
class BirdColors {
  const BirdColors({
    required this.brightness,
    required this.frame,
    required this.toolbar,
    required this.toolbarBorder,
    required this.tabSelected,
    required this.tabHover,
    required this.tabShadow,
    required this.field,
    required this.fieldHover,
    required this.fieldFocused,
    required this.panel,
    required this.panelBorder,
    required this.separator,
    required this.text,
    required this.textSecondary,
    required this.textDisabled,
    required this.icon,
    required this.accent,
    required this.accentHover,
    required this.accentActive,
    required this.onAccent,
    required this.link,
    required this.linkHover,
    required this.selection,
    required this.onSelection,
    required this.control,
    required this.controlHover,
    required this.controlActive,
    required this.inputBackground,
    required this.inputBorder,
    required this.hover,
    required this.pressed,
    required this.danger,
    required this.dangerHover,
    required this.onDanger,
    required this.dangerBackground,
    required this.warning,
    required this.warningBackground,
    required this.success,
    required this.successBackground,
    required this.infoBackground,
    required this.scrim,
    required this.shadow,
  });

  final Brightness brightness;

  /// Behind the tabs, and behind everything else.
  final Color frame;
  final Color toolbar;
  final Color toolbarBorder;
  final Color tabSelected;
  final Color tabHover;
  final Color tabShadow;

  /// The address field and what looks like it.
  final Color field;
  final Color fieldHover;
  final Color fieldFocused;

  /// Menus, popovers and dialogs.
  final Color panel;
  final Color panelBorder;
  final Color separator;

  final Color text;
  final Color textSecondary;
  final Color textDisabled;
  final Color icon;

  /// What is filled in: primary buttons, focus and whatever is switched on.
  final Color accent;
  final Color accentHover;
  final Color accentActive;
  final Color onAccent;

  /// The accent as words and marks on a surface, which in the dark has to be
  /// lighter than a fill to be read.
  final Color link;
  final Color linkHover;

  /// The highlighted row of a menu, which is blue in either theme.
  final Color selection;
  final Color onSelection;

  /// Ordinary buttons.
  final Color control;
  final Color controlHover;
  final Color controlActive;

  final Color inputBackground;
  final Color inputBorder;

  /// Washes over toolbar buttons and rows.
  final Color hover;
  final Color pressed;

  final Color danger;
  final Color dangerHover;
  final Color onDanger;
  final Color dangerBackground;
  final Color warning;
  final Color warningBackground;
  final Color success;
  final Color successBackground;
  final Color infoBackground;

  /// What dims a window under a dialog.
  final Color scrim;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Text selected in a field.
  Color get textSelection => accent.withValues(alpha: 0.35);

  static const BirdColors light = BirdColors(
    brightness: Brightness.light,
    frame: Color(0xFFE5E9F3),
    toolbar: Color(0xFFF6F7FB),
    toolbarBorder: Color(0xFFCDD3E2),
    tabSelected: Color(0xFFFFFFFF),
    tabHover: Color(0x121B2447),
    tabShadow: Color(0x45475578),
    field: Color(0xFFEAEDF5),
    fieldHover: Color(0xFFE3E7F2),
    fieldFocused: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFD2D8E6),
    separator: Color(0xFFE2E6F0),
    text: Color(0xFF11141D),
    textSecondary: Color(0xFF535B73),
    textDisabled: Color(0x6611141D),
    icon: Color(0xFF353C52),
    accent: Color(0xFF1566E6),
    accentHover: Color(0xFF0F55C4),
    accentActive: Color(0xFF0C459F),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF0F57CC),
    linkHover: Color(0xFF0A4099),
    selection: Color(0xFF1566E6),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x178592BC),
    controlHover: Color(0x2B8592BC),
    controlActive: Color(0x4A8592BC),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFF858DA6),
    hover: Color(0x1011141D),
    pressed: Color(0x2011141D),
    danger: Color(0xFFC62F45),
    dangerHover: Color(0xFFA31F33),
    onDanger: Color(0xFFFFFFFF),
    dangerBackground: Color(0xFFFDE8EB),
    warning: Color(0xFF855400),
    warningBackground: Color(0xFFFDF0CC),
    success: Color(0xFF0F714A),
    successBackground: Color(0xFFDDF4E8),
    infoBackground: Color(0xFFE3EEFF),
    scrim: Color(0x5211141D),
    shadow: Color(0x3329324F),
  );

  static const BirdColors dark = BirdColors(
    brightness: Brightness.dark,
    frame: Color(0xFF11141D),
    toolbar: Color(0xFF1B1F2C),
    toolbarBorder: Color(0xFF0A0C12),
    tabSelected: Color(0xFF2C3246),
    tabHover: Color(0x14C3CEF5),
    tabShadow: Color(0x66000000),
    field: Color(0xFF11141D),
    fieldHover: Color(0xFF151925),
    fieldFocused: Color(0xFF262B3C),
    panel: Color(0xFF1F2332),
    panelBorder: Color(0xFF3A4158),
    separator: Color(0xFF30364A),
    text: Color(0xFFEEF1F8),
    textSecondary: Color(0xFFAAB2C9),
    textDisabled: Color(0x66EEF1F8),
    icon: Color(0xFFDDE2EF),
    accent: Color(0xFF1D6DF2),
    accentHover: Color(0xFF1862DD),
    accentActive: Color(0xFF1353BE),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF77ADFF),
    linkHover: Color(0xFFA6C9FF),
    selection: Color(0xFF1D6DF2),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x1CAEBBE8),
    controlHover: Color(0x2BAEBBE8),
    controlActive: Color(0x40AEBBE8),
    inputBackground: Color(0xFF141824),
    inputBorder: Color(0xFF6F7894),
    hover: Color(0x18C3CEF5),
    pressed: Color(0x2CC3CEF5),
    danger: Color(0xFFFF7A87),
    dangerHover: Color(0xFFFFA3AC),
    onDanger: Color(0xFF11141D),
    dangerBackground: Color(0xFF45202C),
    warning: Color(0xFFF2C15C),
    warningBackground: Color(0xFF3C3014),
    success: Color(0xFF5CD3A0),
    successBackground: Color(0xFF13372B),
    infoBackground: Color(0xFF172C52),
    scrim: Color(0x8C05070C),
    shadow: Color(0x80000000),
  );

  static BirdColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  BirdColors copyWith({
    Brightness? brightness,
    Color? panel,
    Color? panelBorder,
    Color? separator,
    Color? text,
    Color? textSecondary,
    Color? textDisabled,
    Color? icon,
    Color? link,
    Color? inputBackground,
    Color? inputBorder,
    Color? hover,
    Color? pressed,
  }) => BirdColors(
    brightness: brightness ?? this.brightness,
    frame: frame,
    toolbar: toolbar,
    toolbarBorder: toolbarBorder,
    tabSelected: tabSelected,
    tabHover: tabHover,
    tabShadow: tabShadow,
    field: field,
    fieldHover: fieldHover,
    fieldFocused: fieldFocused,
    panel: panel ?? this.panel,
    panelBorder: panelBorder ?? this.panelBorder,
    separator: separator ?? this.separator,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled: textDisabled ?? this.textDisabled,
    icon: icon ?? this.icon,
    accent: accent,
    accentHover: accentHover,
    accentActive: accentActive,
    onAccent: onAccent,
    link: link ?? this.link,
    linkHover: linkHover,
    selection: selection,
    onSelection: onSelection,
    control: control,
    controlHover: controlHover,
    controlActive: controlActive,
    inputBackground: inputBackground ?? this.inputBackground,
    inputBorder: inputBorder ?? this.inputBorder,
    hover: hover ?? this.hover,
    pressed: pressed ?? this.pressed,
    danger: danger,
    dangerHover: dangerHover,
    onDanger: onDanger,
    dangerBackground: dangerBackground,
    warning: warning,
    warningBackground: warningBackground,
    success: success,
    successBackground: successBackground,
    infoBackground: infoBackground,
    scrim: scrim,
    shadow: shadow,
  );
}

/// The system's own faces, as Firefox uses for its interface.
abstract final class BirdFonts {
  static const String ui = '.AppleSystemUIFont';
  static const List<String> uiFallback = ['Segoe UI', 'Ubuntu', 'Roboto', 'sans-serif'];
  static const String mono = 'Menlo';
  static const List<String> monoFallback = [
    'SF Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'Roboto Mono',
    'monospace',
  ];
}

/// Text sizes. Desktop interfaces are small and even: most of it is [body].
abstract final class BirdTextSize {
  static const double caption = 11;
  static const double small = 12;
  static const double body = 13;
  static const double headline = 15;
  static const double title = 17;
}

abstract final class BirdRadius {
  static const double control = 4;
  static const double menu = 6;
  static const double panel = 8;
  static const double dialog = 10;
}

class BirdTheme extends InheritedWidget {
  const BirdTheme({super.key, required this.colors, required super.child});

  final BirdColors colors;

  static BirdColors of(BuildContext context) => maybeOf(context) ?? BirdColors.light;

  /// Null outside a Bird interface, such as under a Material app.
  static BirdColors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BirdTheme>()?.colors;

  @override
  bool updateShouldNotify(BirdTheme oldWidget) => oldWidget.colors != colors;
}

extension BirdThemeContext on BuildContext {
  BirdColors get bird => BirdTheme.of(this);

  /// Text of the interface.
  TextStyle birdText({
    Color? color,
    double size = BirdTextSize.body,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
  }) => TextStyle(
    inherit: false,
    fontFamily: BirdFonts.ui,
    fontFamilyFallback: BirdFonts.uiFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: color ?? bird.text,
    textBaseline: TextBaseline.alphabetic,
    decoration: TextDecoration.none,
    leadingDistribution: TextLeadingDistribution.even,
  );
}
