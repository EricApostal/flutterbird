import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

import '../util/syntax.dart';

/// The colours of the developer tools: the browser's own blue and blue-tinted
/// greys, with a set of its own for code.
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

  // Fills that white reads on, the same in either theme: counts, badges and
  // the marks beside messages.
  static const Color errorFill = Color(0xFFC62F45);
  static const Color warningFill = Color(0xFF855400);
  static const Color infoFill = Color(0xFF1566E6);

  /// What shows a flex or grid container, in the markup and the layout view.
  static const Color layoutMark = Color(0xFF6A41C9);

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
    link: accent,
    inputBackground: inputBackground,
    inputBorder: inputBorder,
    hover: toolbarHover,
    pressed: toolbarActive,
  );

  static const DtColors light = DtColors(
    brightness: Brightness.light,
    body: Color(0xFFFFFFFF),
    sidebar: Color(0xFFFFFFFF),
    toolbar: Color(0xFFF6F7FB),
    tabToolbar: Color(0xFFF0F2F8),
    toolbarHover: Color(0x1011141D),
    toolbarActive: Color(0x2211141D),
    splitter: Color(0xFFE0E4EF),
    splitterStrong: Color(0xFFAEB6CC),
    selection: Color(0xFF1566E6),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFFD6DBEA),
    rowHover: Color(0xFFEEF4FF),
    rowAlternate: Color(0xFFFAFBFD),
    text: Color(0xFF343A4E),
    textStrong: Color(0xFF11141D),
    textDim: Color(0xFF626A83),
    comment: Color(0xFF656D86),
    accent: Color(0xFF0F57CC),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFC5CCDE),
    popup: Color(0xFFFFFFFF),
    popupBorder: Color(0xFFB9C0D4),
    popupHover: Color(0xFFE7F0FF),
    blue: Color(0xFF0F57CC),
    green: Color(0xFF0F714A),
    red: Color(0xFFC62F45),
    purple: Color(0xFF6A41C9),
    pink: Color(0xFFAD2F72),
    yellow: Color(0xFF7A5200),
    orange: Color(0xFFA84B00),
    errorBackground: Color(0xFFFEF0F2),
    errorBorder: Color(0xFFF7C5CD),
    errorText: Color(0xFF9D1730),
    warningBackground: Color(0xFFFDF5DA),
    warningBorder: Color(0xFFEFDD9C),
    warningText: Color(0xFF6E4600),
    warningIcon: Color(0xFFD29B14),
    tag: Color(0xFF0F57CC),
    attributeName: Color(0xFF08706F),
    attributeValue: Color(0xFF6A41C9),
    cssProperty: Color(0xFF0B6A78),
    cssValue: Color(0xFF3F3AAE),
    syntaxKeyword: Color(0xFF6A41C9),
    syntaxString: Color(0xFF0F714A),
    syntaxNumber: Color(0xFFA84B00),
    syntaxFunction: Color(0xFF0F57CC),
    syntaxVariable: Color(0xFF11141D),
    syntaxProperty: Color(0xFF0B6A78),
    syntaxLiteral: Color(0xFFAD2F72),
    objectKey: Color(0xFF0B6A78),
    objectString: Color(0xFF0F714A),
    objectNumber: Color(0xFFA84B00),
    objectClass: Color(0xFF0F57CC),
    flash: Color(0x66FFD54A),
    paused: Color(0xFFFFF1C2),
    pausedBorder: Color(0xFFD9A92A),
    breakpoint: Color(0xFF2A6FE0),
    searchHit: Color(0x80FFD54A),
  );

  static const DtColors dark = DtColors(
    brightness: Brightness.dark,
    body: Color(0xFF171B27),
    sidebar: Color(0xFF171B27),
    toolbar: Color(0xFF1B1F2C),
    tabToolbar: Color(0xFF11141D),
    toolbarHover: Color(0x18C3CEF5),
    toolbarActive: Color(0x2CC3CEF5),
    splitter: Color(0xFF2C3246),
    splitterStrong: Color(0xFF4A526C),
    selection: Color(0xFF1F4F9E),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFF353C53),
    rowHover: Color(0xFF222838),
    rowAlternate: Color(0xFF1A1E2B),
    text: Color(0xFFB7BFD4),
    textStrong: Color(0xFFEEF1F8),
    textDim: Color(0xFF8F98B3),
    comment: Color(0xFF8790AC),
    accent: Color(0xFF77ADFF),
    inputBackground: Color(0xFF11141D),
    inputBorder: Color(0xFF3A4158),
    popup: Color(0xFF1F2332),
    popupBorder: Color(0xFF434A63),
    popupHover: Color(0xFF2C3347),
    blue: Color(0xFF77ADFF),
    green: Color(0xFF6FD6A6),
    red: Color(0xFFFF7A87),
    purple: Color(0xFFB9A4FF),
    pink: Color(0xFFF494C4),
    yellow: Color(0xFFF2D06B),
    orange: Color(0xFFF2A766),
    errorBackground: Color(0xFF3B1E29),
    errorBorder: Color(0xFF63303E),
    errorText: Color(0xFFFFB8C0),
    warningBackground: Color(0xFF37301A),
    warningBorder: Color(0xFF5A4B1F),
    warningText: Color(0xFFF6D98F),
    warningIcon: Color(0xFFF2C15C),
    tag: Color(0xFF77ADFF),
    attributeName: Color(0xFF63D0CB),
    attributeValue: Color(0xFFC3B1FF),
    cssProperty: Color(0xFF6CCFDD),
    cssValue: Color(0xFFB6BCFF),
    syntaxKeyword: Color(0xFFB9A4FF),
    syntaxString: Color(0xFF8BDBA8),
    syntaxNumber: Color(0xFFF2A766),
    syntaxFunction: Color(0xFF77ADFF),
    syntaxVariable: Color(0xFFDCE1EE),
    syntaxProperty: Color(0xFF6CCFDD),
    syntaxLiteral: Color(0xFFF494C4),
    objectKey: Color(0xFF6CCFDD),
    objectString: Color(0xFF8BDBA8),
    objectNumber: Color(0xFFF2A766),
    objectClass: Color(0xFF77ADFF),
    flash: Color(0x59C59A1E),
    paused: Color(0xFF433A1C),
    pausedBorder: Color(0xFF8C7526),
    breakpoint: Color(0xFF4F83D9),
    searchHit: Color(0x80735C12),
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

/// The fonts of the tools: the system's own, and Menlo for code.
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
