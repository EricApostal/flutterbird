import 'package:flutter/widgets.dart';

/// The colours of the browser's own interface, after Firefox's desktop theme.
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

  /// Primary buttons, links, focus and whatever is switched on.
  final Color accent;
  final Color accentHover;
  final Color accentActive;
  final Color onAccent;

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
    frame: Color(0xFFEAEAED),
    toolbar: Color(0xFFF9F9FB),
    toolbarBorder: Color(0xFFCFCFD8),
    tabSelected: Color(0xFFFFFFFF),
    tabHover: Color(0x14000000),
    tabShadow: Color(0x4D80808E),
    field: Color(0xFFF0F0F4),
    fieldHover: Color(0xFFEAEAEF),
    fieldFocused: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFCFCFD8),
    separator: Color(0xFFE0E0E6),
    text: Color(0xFF15141A),
    textSecondary: Color(0xFF5B5B66),
    textDisabled: Color(0x6615141A),
    icon: Color(0xFF3A3944),
    accent: Color(0xFF0061E0),
    accentHover: Color(0xFF0250BB),
    accentActive: Color(0xFF053E94),
    onAccent: Color(0xFFFFFFFF),
    selection: Color(0xFF0061E0),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x54CFCFD8),
    controlHover: Color(0xA8CFCFD8),
    controlActive: Color(0xFFCFCFD8),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFF8F8F9D),
    hover: Color(0x1215141A),
    pressed: Color(0x2415141A),
    danger: Color(0xFFC50042),
    dangerHover: Color(0xFF810220),
    onDanger: Color(0xFFFFFFFF),
    dangerBackground: Color(0xFFFFE8E8),
    warning: Color(0xFF8A6100),
    warningBackground: Color(0xFFFFF4CE),
    success: Color(0xFF017A40),
    successBackground: Color(0xFFD8F8E4),
    infoBackground: Color(0xFFE5F0FF),
    scrim: Color(0x4D000000),
    shadow: Color(0x333A3944),
  );

  static const BirdColors dark = BirdColors(
    brightness: Brightness.dark,
    frame: Color(0xFF1C1B22),
    toolbar: Color(0xFF2B2A33),
    toolbarBorder: Color(0xFF0C0C0D),
    tabSelected: Color(0xFF42414D),
    tabHover: Color(0x14FBFBFE),
    tabShadow: Color(0x66000000),
    field: Color(0xFF1C1B22),
    fieldHover: Color(0xFF201F27),
    fieldFocused: Color(0xFF42414D),
    panel: Color(0xFF2B2A33),
    panelBorder: Color(0xFF52525E),
    separator: Color(0xFF45444F),
    text: Color(0xFFFBFBFE),
    textSecondary: Color(0xFFBFBFC9),
    textDisabled: Color(0x66FBFBFE),
    icon: Color(0xFFE9E9EE),
    accent: Color(0xFF00DDFF),
    accentHover: Color(0xFF80EBFF),
    accentActive: Color(0xFFAAF2FF),
    onAccent: Color(0xFF2B2A33),
    selection: Color(0xFF0061E0),
    onSelection: Color(0xFFFFFFFF),
    control: Color(0x1AFBFBFE),
    controlHover: Color(0x29FBFBFE),
    controlActive: Color(0x3DFBFBFE),
    inputBackground: Color(0xFF1C1B22),
    inputBorder: Color(0xFF8F8F9D),
    hover: Color(0x1AFBFBFE),
    pressed: Color(0x30FBFBFE),
    danger: Color(0xFFFF848B),
    dangerHover: Color(0xFFFFBDC5),
    onDanger: Color(0xFF2B2A33),
    dangerBackground: Color(0xFF55222B),
    warning: Color(0xFFFFD567),
    warningBackground: Color(0xFF4E3A0F),
    success: Color(0xFF86DEAD),
    successBackground: Color(0xFF0F4429),
    infoBackground: Color(0xFF13345C),
    scrim: Color(0x80000000),
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
    Color? accent,
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
    accent: accent ?? this.accent,
    accentHover: accentHover,
    accentActive: accentActive,
    onAccent: onAccent,
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
