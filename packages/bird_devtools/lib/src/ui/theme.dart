import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

import '../util/syntax.dart';

/// The colours of Firefox's developer tools, from its Photon theme variables.
class DtColors {
  const DtColors({
    required this.brightness,
    required this.body,
    required this.sidebar,
    required this.toolbar,
    required this.tabToolbar,
    required this.toolbarHover,
    required this.toolbarActive,
    required this.splitter,
    required this.splitterStrong,
    required this.selection,
    required this.selectionText,
    required this.selectionInactive,
    required this.rowHover,
    required this.rowAlternate,
    required this.text,
    required this.textStrong,
    required this.textDim,
    required this.comment,
    required this.accent,
    required this.inputBackground,
    required this.inputBorder,
    required this.popup,
    required this.popupBorder,
    required this.popupHover,
    required this.blue,
    required this.green,
    required this.red,
    required this.purple,
    required this.pink,
    required this.yellow,
    required this.orange,
    required this.errorBackground,
    required this.errorBorder,
    required this.errorText,
    required this.warningBackground,
    required this.warningBorder,
    required this.warningText,
    required this.warningIcon,
    required this.tag,
    required this.attributeName,
    required this.attributeValue,
    required this.cssProperty,
    required this.cssValue,
    required this.syntaxKeyword,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxFunction,
    required this.syntaxVariable,
    required this.syntaxProperty,
    required this.syntaxLiteral,
    required this.objectKey,
    required this.objectString,
    required this.objectNumber,
    required this.objectClass,
    required this.flash,
    required this.paused,
    required this.pausedBorder,
    required this.breakpoint,
    required this.searchHit,
  });

  final Brightness brightness;
  final Color body;
  final Color sidebar;
  final Color toolbar;
  final Color tabToolbar;
  final Color toolbarHover;
  final Color toolbarActive;
  final Color splitter;
  final Color splitterStrong;
  final Color selection;
  final Color selectionText;
  final Color selectionInactive;
  final Color rowHover;
  final Color rowAlternate;
  final Color text;
  final Color textStrong;
  final Color textDim;
  final Color comment;
  final Color accent;
  final Color inputBackground;
  final Color inputBorder;
  final Color popup;
  final Color popupBorder;
  final Color popupHover;
  final Color blue;
  final Color green;
  final Color red;
  final Color purple;
  final Color pink;
  final Color yellow;
  final Color orange;
  final Color errorBackground;
  final Color errorBorder;
  final Color errorText;
  final Color warningBackground;
  final Color warningBorder;
  final Color warningText;
  final Color warningIcon;
  final Color tag;
  final Color attributeName;
  final Color attributeValue;
  final Color cssProperty;
  final Color cssValue;
  final Color syntaxKeyword;
  final Color syntaxString;
  final Color syntaxNumber;
  final Color syntaxFunction;
  final Color syntaxVariable;
  final Color syntaxProperty;
  final Color syntaxLiteral;
  final Color objectKey;
  final Color objectString;
  final Color objectNumber;
  final Color objectClass;
  final Color flash;
  final Color paused;
  final Color pausedBorder;
  final Color breakpoint;
  final Color searchHit;

  bool get isDark => brightness == Brightness.dark;

  /// These colours as the shared widgets know them: their menus, tooltips,
  /// fields and scroll bars.
  BirdColors get bird => BirdColors.forBrightness(brightness).copyWith(
    panel: popup,
    panelBorder: popupBorder,
    separator: splitter,
    text: textStrong,
    textSecondary: textDim,
    textDisabled: textDim.withValues(alpha: 0.55),
    icon: text,
    accent: accent,
    inputBackground: inputBackground,
    inputBorder: inputBorder,
    hover: toolbarHover,
    pressed: toolbarActive,
  );

  static const DtColors light = DtColors(
    brightness: Brightness.light,
    body: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    toolbar: Color(0xFFF9F9FA),
    tabToolbar: Color(0xFFF9F9FA),
    toolbarHover: Color(0x14000000),
    toolbarActive: Color(0x26000000),
    splitter: Color(0xFFE0E0E2),
    splitterStrong: Color(0xFFB1B1B3),
    selection: Color(0xFF0060DF),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFFD7D7DB),
    rowHover: Color(0xFFF0F9FE),
    rowAlternate: Color(0xFFFCFCFD),
    text: Color(0xFF38383D),
    textStrong: Color(0xFF0C0C0D),
    textDim: Color(0xFF737373),
    comment: Color(0xFF747474),
    accent: Color(0xFF0074E8),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCCCCCF),
    popup: Color(0xFFFFFFFF),
    popupBorder: Color(0xFFB1B1B3),
    popupHover: Color(0xFFE8F2FD),
    blue: Color(0xFF0074E8),
    green: Color(0xFF058B00),
    red: Color(0xFFD70022),
    purple: Color(0xFF8000D7),
    pink: Color(0xFFDD00A9),
    yellow: Color(0xFF715100),
    orange: Color(0xFFD76E00),
    errorBackground: Color(0xFFFDF2F5),
    errorBorder: Color(0xFFFFCCD5),
    errorText: Color(0xFFA4000F),
    warningBackground: Color(0xFFFFFBD6),
    warningBorder: Color(0xFFF5E8A0),
    warningText: Color(0xFF715100),
    warningIcon: Color(0xFFD7B600),
    tag: Color(0xFF0074E8),
    attributeName: Color(0xFFDD00A9),
    attributeValue: Color(0xFF003EAA),
    cssProperty: Color(0xFF0058B8),
    cssValue: Color(0xFFB5007F),
    syntaxKeyword: Color(0xFFDD00A9),
    syntaxString: Color(0xFF8000D7),
    syntaxNumber: Color(0xFF058B00),
    syntaxFunction: Color(0xFF0060DF),
    syntaxVariable: Color(0xFF0C0C0D),
    syntaxProperty: Color(0xFF003EAA),
    syntaxLiteral: Color(0xFF8000D7),
    objectKey: Color(0xFF0074E8),
    objectString: Color(0xFFDD00A9),
    objectNumber: Color(0xFF058B00),
    objectClass: Color(0xFF003EAA),
    flash: Color(0x66FFE900),
    paused: Color(0xFFFFF6BF),
    pausedBorder: Color(0xFFE5C800),
    breakpoint: Color(0xFF0074E8),
    searchHit: Color(0x80FFE900),
  );

  static const DtColors dark = DtColors(
    brightness: Brightness.dark,
    body: Color(0xFF232327),
    sidebar: Color(0xFF232327),
    toolbar: Color(0xFF18181A),
    tabToolbar: Color(0xFF0C0C0D),
    toolbarHover: Color(0x1FFFFFFF),
    toolbarActive: Color(0x33FFFFFF),
    splitter: Color(0xFF38383D),
    splitterStrong: Color(0xFF5A5A60),
    selection: Color(0xFF204E8A),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFF424248),
    rowHover: Color(0xFF2C2C33),
    rowAlternate: Color(0xFF27272B),
    text: Color(0xFFB1B1B3),
    textStrong: Color(0xFFF9F9FA),
    textDim: Color(0xFF939395),
    comment: Color(0xFF939395),
    accent: Color(0xFF75BFFF),
    inputBackground: Color(0xFF1B1B1F),
    inputBorder: Color(0xFF45454C),
    popup: Color(0xFF2A2A2E),
    popupBorder: Color(0xFF52525E),
    popupHover: Color(0xFF3F3F46),
    blue: Color(0xFF75BFFF),
    green: Color(0xFF86DE74),
    red: Color(0xFFFF7DE9),
    purple: Color(0xFFB98EFF),
    pink: Color(0xFFFF7DE9),
    yellow: Color(0xFFFFE900),
    orange: Color(0xFFFFB454),
    errorBackground: Color(0xFF4B2F36),
    errorBorder: Color(0xFF6C3B45),
    errorText: Color(0xFFFFB3C0),
    warningBackground: Color(0xFF42381F),
    warningBorder: Color(0xFF5C4D1E),
    warningText: Color(0xFFFCE19F),
    warningIcon: Color(0xFFFFE900),
    tag: Color(0xFF75BFFF),
    attributeName: Color(0xFFFF97E2),
    attributeValue: Color(0xFFB98EFF),
    cssProperty: Color(0xFF75BFFF),
    cssValue: Color(0xFFFF7DE9),
    syntaxKeyword: Color(0xFFFF7DE9),
    syntaxString: Color(0xFF6B89FF),
    syntaxNumber: Color(0xFF86DE74),
    syntaxFunction: Color(0xFF75BFFF),
    syntaxVariable: Color(0xFFD7D7DB),
    syntaxProperty: Color(0xFF75BFFF),
    syntaxLiteral: Color(0xFFB98EFF),
    objectKey: Color(0xFF75BFFF),
    objectString: Color(0xFFFF7DE9),
    objectNumber: Color(0xFF86DE74),
    objectClass: Color(0xFF75BFFF),
    flash: Color(0x59A47F00),
    paused: Color(0xFF4A4320),
    pausedBorder: Color(0xFF8F7F20),
    breakpoint: Color(0xFF5675B9),
    searchHit: Color(0x806B5B00),
  );

  Color syntax(TokenKind kind) => switch (kind) {
    TokenKind.keyword => syntaxKeyword,
    TokenKind.string => syntaxString,
    TokenKind.number => syntaxNumber,
    TokenKind.comment => comment,
    TokenKind.literal => syntaxLiteral,
    TokenKind.function => syntaxFunction,
    TokenKind.property => syntaxProperty,
    TokenKind.punctuation => text,
    TokenKind.tag => tag,
    TokenKind.attributeName => attributeName,
    TokenKind.attributeValue => attributeValue,
    TokenKind.selector => tag,
    TokenKind.atRule => syntaxKeyword,
    TokenKind.variable => syntaxVariable,
    TokenKind.regexp => syntaxString,
    TokenKind.plain => text,
  };
}

/// The fonts of the tools. Firefox uses the system's own for its chrome.
class DtFonts {
  static const String ui = BirdFonts.ui;
  static const List<String> uiFallback = BirdFonts.uiFallback;
  static const String mono = BirdFonts.mono;
  static const List<String> monoFallback = BirdFonts.monoFallback;

  static const double uiSize = 12;
  static const double monoSize = 11;

  /// The height of one line of code.
  static const double codeLine = 16;
}

class DtTheme extends InheritedWidget {
  const DtTheme({super.key, required this.colors, required super.child});

  final DtColors colors;

  static DtColors of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DtTheme>()?.colors ??
      DtColors.light;

  @override
  bool updateShouldNotify(DtTheme oldWidget) => oldWidget.colors != colors;
}

extension DtThemeContext on BuildContext {
  DtColors get dt => DtTheme.of(this);

  /// Text of the tools' chrome.
  TextStyle uiStyle({
    Color? color,
    double size = DtFonts.uiSize,
    FontWeight? weight,
    FontStyle? style,
  }) => TextStyle(
    inherit: false,
    fontFamily: DtFonts.ui,
    fontFamilyFallback: DtFonts.uiFallback,
    fontSize: size,
    height: 1.25,
    fontWeight: weight ?? FontWeight.w400,
    fontStyle: style ?? FontStyle.normal,
    color: color ?? dt.text,
    textBaseline: TextBaseline.alphabetic,
    decoration: TextDecoration.none,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Text that is code.
  TextStyle monoStyle({
    Color? color,
    double size = DtFonts.monoSize,
    FontWeight? weight,
    FontStyle? style,
    TextDecoration? decoration,
  }) => TextStyle(
    inherit: false,
    fontFamily: DtFonts.mono,
    fontFamilyFallback: DtFonts.monoFallback,
    fontSize: size,
    height: DtFonts.codeLine / DtFonts.monoSize,
    fontWeight: weight ?? FontWeight.w400,
    fontStyle: style ?? FontStyle.normal,
    color: color ?? dt.text,
    textBaseline: TextBaseline.alphabetic,
    decoration: decoration ?? TextDecoration.none,
    decorationColor: color ?? dt.text,
    leadingDistribution: TextLeadingDistribution.even,
  );
}
