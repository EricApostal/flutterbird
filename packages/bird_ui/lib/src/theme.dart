import 'package:flutter/widgets.dart';

/// The two colours of Rubisco's mark: the blue of its ring, and the blue-black
/// behind it. The palettes are quieter takes on them, with greys that are only
/// slightly cool, so that the interface stays out of the page's way.
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
    frame: Color(0xFFE8E9EC),
    toolbar: Color(0xFFF7F7F8),
    toolbarBorder: Color(0xFFD1D3D8),
    tabSelected: Color(0xFFFFFFFF),
    tabHover: Color(0x12232731),
    tabShadow: Color(0x45515660),
    field: Color(0xFFECEDEF),
    fieldHover: Color(0xFFE6E7EA),
    fieldFocused: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFD6D8DC),
    separator: Color(0xFFE5E6E9),
    text: Color(0xFF131417),
    textSecondary: Color(0xFF595C63),
    textDisabled: Color(0x66131417),
    icon: Color(0xFF3A3D43),
    accent: Color(0xFF3C6DC1),
    accentHover: Color(0xFF315CA4),
    accentActive: Color(0xFF274A85),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF325EAB),
    linkHover: Color(0xFF244580),
    selection: Color(0xFF3C6DC1),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x178F93A0),
    controlHover: Color(0x2B8F93A0),
    controlActive: Color(0x4A8F93A0),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFF8B8E95),
    hover: Color(0x10131417),
    pressed: Color(0x20131417),
    danger: Color(0xFFB9434E),
    dangerHover: Color(0xFF98323B),
    onDanger: Color(0xFFFFFFFF),
    dangerBackground: Color(0xFFFAE9EC),
    warning: Color(0xFF7F5722),
    warningBackground: Color(0xFFFBF0D3),
    success: Color(0xFF2B6E4E),
    successBackground: Color(0xFFE0F3E9),
    infoBackground: Color(0xFFE6EEF9),
    scrim: Color(0x52131417),
    shadow: Color(0x3330333C),
  );

  static const BirdColors dark = BirdColors(
    brightness: Brightness.dark,
    frame: Color(0xFF131417),
    toolbar: Color(0xFF1E1F23),
    toolbarBorder: Color(0xFF0C0C0E),
    tabSelected: Color(0xFF313339),
    tabHover: Color(0x14CCCFDB),
    tabShadow: Color(0x66000000),
    field: Color(0xFF131417),
    fieldHover: Color(0xFF18191D),
    fieldFocused: Color(0xFF2A2C31),
    panel: Color(0xFF222428),
    panelBorder: Color(0xFF404249),
    separator: Color(0xFF35373D),
    text: Color(0xFFF0F1F3),
    textSecondary: Color(0xFFB0B2B9),
    textDisabled: Color(0x66F0F1F3),
    icon: Color(0xFFE1E2E6),
    accent: Color(0xFF4275CC),
    accentHover: Color(0xFF3B69BA),
    accentActive: Color(0xFF31599F),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF89AEE5),
    linkHover: Color(0xFFB1C9ED),
    selection: Color(0xFF4275CC),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x1CB8BCCA),
    controlHover: Color(0x2BB8BCCA),
    controlActive: Color(0x40B8BCCA),
    inputBackground: Color(0xFF17181C),
    inputBorder: Color(0xFF767981),
    hover: Color(0x18CCCFDB),
    pressed: Color(0x2CCCCFDB),
    danger: Color(0xFFF2858D),
    dangerHover: Color(0xFFF5A9B0),
    onDanger: Color(0xFF131417),
    dangerBackground: Color(0xFF41232C),
    warning: Color(0xFFEBC375),
    warningBackground: Color(0xFF3A301A),
    success: Color(0xFF73CFA5),
    successBackground: Color(0xFF1A362C),
    infoBackground: Color(0xFF1F2D47),
    scrim: Color(0x8C060708),
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
