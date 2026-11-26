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
  static const Color errorFill = Color(0xFFB9434E);
  static const Color warningFill = Color(0xFF7F5722);
  static const Color infoFill = Color(0xFF3C6DC1);

  /// What shows a flex or grid container, in the markup and the layout view.
  static const Color layoutMark = Color(0xFF684CB7);

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
    toolbar: Color(0xFFF7F7F8),
    tabToolbar: Color(0xFFF1F2F4),
    toolbarHover: Color(0x10131417),
    toolbarActive: Color(0x22131417),
    splitter: Color(0xFFE3E4E7),
    splitterStrong: Color(0xFFB4B6BD),
    selection: Color(0xFF3C6DC1),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFFDADBE0),
    rowHover: Color(0xFFF0F4FB),
    rowAlternate: Color(0xFFFBFBFC),
    text: Color(0xFF393B41),
    textStrong: Color(0xFF131417),
    textDim: Color(0xFF686B72),
    comment: Color(0xFF6B6E75),
    accent: Color(0xFF325EAB),
    inputBackground: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFCACCD1),
    popup: Color(0xFFFFFFFF),
    popupBorder: Color(0xFFBEC0C6),
    popupHover: Color(0xFFEAF0FA),
    blue: Color(0xFF325EAB),
    green: Color(0xFF2B6E4E),
    red: Color(0xFFB9434E),
    purple: Color(0xFF684CB7),
    pink: Color(0xFFA33F70),
    yellow: Color(0xFF75541F),
    orange: Color(0xFF9E5326),
    errorBackground: Color(0xFFFCF1F2),
    errorBorder: Color(0xFFF1C8CE),
    errorText: Color(0xFF922C38),
    warningBackground: Color(0xFFFCF5DF),
    warningBorder: Color(0xFFECDDA9),
    warningText: Color(0xFF69481B),
    warningIcon: Color(0xFFCA9E44),
    tag: Color(0xFF325EAB),
    attributeName: Color(0xFF296E6D),
    attributeValue: Color(0xFF684CB7),
    cssProperty: Color(0xFF286873),
    cssValue: Color(0xFF424691),
    syntaxKeyword: Color(0xFF684CB7),
    syntaxString: Color(0xFF2B6E4E),
    syntaxNumber: Color(0xFF9E5326),
    syntaxFunction: Color(0xFF325EAB),
    syntaxVariable: Color(0xFF131417),
    syntaxProperty: Color(0xFF286873),
    syntaxLiteral: Color(0xFFA33F70),
    objectKey: Color(0xFF286873),
    objectString: Color(0xFF2B6E4E),
    objectNumber: Color(0xFF9E5326),
    objectClass: Color(0xFF325EAB),
    flash: Color(0x66F8D66F),
    paused: Color(0xFFFCF1CB),
    pausedBorder: Color(0xFFD2AB50),
    breakpoint: Color(0xFF4774BF),
    searchHit: Color(0x80F8D66F),
  );

  static const DtColors dark = DtColors(
    brightness: Brightness.dark,
    body: Color(0xFF1A1B1F),
    sidebar: Color(0xFF1A1B1F),
    toolbar: Color(0xFF1E1F23),
    tabToolbar: Color(0xFF131417),
    toolbarHover: Color(0x18CCCFDB),
    toolbarActive: Color(0x2CCCCFDB),
    splitter: Color(0xFF313339),
    splitterStrong: Color(0xFF50535B),
    selection: Color(0xFF335287),
    selectionText: Color(0xFFFFFFFF),
    selectionInactive: Color(0xFF3B3D44),
    rowHover: Color(0xFF242833),
    rowAlternate: Color(0xFF1D1E22),
    text: Color(0xFFBDBFC5),
    textStrong: Color(0xFFF0F1F3),
    textDim: Color(0xFF9699A1),
    comment: Color(0xFF8E9199),
    accent: Color(0xFF89AEE5),
    inputBackground: Color(0xFF131417),
    inputBorder: Color(0xFF404249),
    popup: Color(0xFF222428),
    popupBorder: Color(0xFF494B52),
    popupHover: Color(0xFF2E3341),
    blue: Color(0xFF89AEE5),
    green: Color(0xFF81D2AA),
    red: Color(0xFFF2858D),
    purple: Color(0xFFB8A8F2),
    pink: Color(0xFFEA9BC2),
    yellow: Color(0xFFECD182),
    orange: Color(0xFFE9AB78),
    errorBackground: Color(0xFF382029),
    errorBorder: Color(0xFF5E343F),
    errorText: Color(0xFFF7BCC2),
    warningBackground: Color(0xFF36301F),
    warningBorder: Color(0xFF584B29),
    warningText: Color(0xFFF1DA9E),
    warningIcon: Color(0xFFEBC375),
    tag: Color(0xFF89AEE5),
    attributeName: Color(0xFF78CDC8),
    attributeValue: Color(0xFFC2B4F4),
    cssProperty: Color(0xFF7FCCD7),
    cssValue: Color(0xFFBABEEC),
    syntaxKeyword: Color(0xFFB8A8F2),
    syntaxString: Color(0xFF98D7AE),
    syntaxNumber: Color(0xFFE9AB78),
    syntaxFunction: Color(0xFF89AEE5),
    syntaxVariable: Color(0xFFE0E1E5),
    syntaxProperty: Color(0xFF7FCCD7),
    syntaxLiteral: Color(0xFFEA9BC2),
    objectKey: Color(0xFF7FCCD7),
    objectString: Color(0xFF98D7AE),
    objectNumber: Color(0xFFE9AB78),
    objectClass: Color(0xFF89AEE5),
    flash: Color(0x59BF9C45),
    paused: Color(0xFF413A22),
    pausedBorder: Color(0xFF88763A),
    breakpoint: Color(0xFF6285BF),
    searchHit: Color(0x806F5D28),
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
