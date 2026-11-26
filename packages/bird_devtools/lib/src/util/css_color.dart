import 'dart:ui' show Color;

const String _named =
    'aliceblue:f0f8ff antiquewhite:faebd7 aqua:00ffff aquamarine:7fffd4 azure:f0ffff beige:f5f5dc bisque:ffe4c4 black:000000 blanchedalmond:ffebcd blue:0000ff blueviolet:8a2be2 brown:a52a2a burlywood:deb887 cadetblue:5f9ea0 chartreuse:7fff00 chocolate:d2691e coral:ff7f50 cornflowerblue:6495ed cornsilk:fff8dc crimson:dc143c cyan:00ffff darkblue:00008b darkcyan:008b8b darkgoldenrod:b8860b darkgray:a9a9a9 darkgreen:006400 darkgrey:a9a9a9 darkkhaki:bdb76b darkmagenta:8b008b darkolivegreen:556b2f darkorange:ff8c00 darkorchid:9932cc darkred:8b0000 darksalmon:e9967a darkseagreen:8fbc8f darkslateblue:483d8b darkslategray:2f4f4f darkslategrey:2f4f4f darkturquoise:00ced1 darkviolet:9400d3 deeppink:ff1493 deepskyblue:00bfff dimgray:696969 dimgrey:696969 dodgerblue:1e90ff firebrick:b22222 floralwhite:fffaf0 forestgreen:228b22 fuchsia:ff00ff gainsboro:dcdcdc ghostwhite:f8f8ff gold:ffd700 goldenrod:daa520 gray:808080 green:008000 greenyellow:adff2f grey:808080 honeydew:f0fff0 hotpink:ff69b4 indianred:cd5c5c indigo:4b0082 ivory:fffff0 khaki:f0e68c lavender:e6e6fa lavenderblush:fff0f5 lawngreen:7cfc00 lemonchiffon:fffacd lightblue:add8e6 lightcoral:f08080 lightcyan:e0ffff lightgoldenrodyellow:fafad2 lightgray:d3d3d3 lightgreen:90ee90 lightgrey:d3d3d3 lightpink:ffb6c1 lightsalmon:ffa07a lightseagreen:20b2aa lightskyblue:87cefa lightslategray:778899 lightslategrey:778899 lightsteelblue:b0c4de lightyellow:ffffe0 lime:00ff00 limegreen:32cd32 linen:faf0e6 magenta:ff00ff maroon:800000 mediumaquamarine:66cdaa mediumblue:0000cd mediumorchid:ba55d3 mediumpurple:9370db mediumseagreen:3cb371 mediumslateblue:7b68ee mediumspringgreen:00fa9a mediumturquoise:48d1cc mediumvioletred:c71585 midnightblue:191970 mintcream:f5fffa mistyrose:ffe4e1 moccasin:ffe4b5 navajowhite:ffdead navy:000080 oldlace:fdf5e6 olive:808000 olivedrab:6b8e23 orange:ffa500 orangered:ff4500 orchid:da70d6 palegoldenrod:eee8aa palegreen:98fb98 paleturquoise:afeeee palevioletred:db7093 papayawhip:ffefd5 peachpuff:ffdab9 peru:cd853f pink:ffc0cb plum:dda0dd powderblue:b0e0e6 purple:800080 rebeccapurple:663399 red:ff0000 rosybrown:bc8f8f royalblue:4169e1 saddlebrown:8b4513 salmon:fa8072 sandybrown:f4a460 seagreen:2e8b57 seashell:fff5ee sienna:a0522d silver:c0c0c0 skyblue:87ceeb slateblue:6a5acd slategray:708090 slategrey:708090 snow:fffafa springgreen:00ff7f steelblue:4682b4 tan:d2b48c teal:008080 thistle:d8bfd8 tomato:ff6347 turquoise:40e0d0 violet:ee82ee wheat:f5deb3 white:ffffff whitesmoke:f5f5f5 yellow:ffff00 yellowgreen:9acd32';

final Map<String, int> cssNamedColors = {
  for (final entry in _named.split(' '))
    entry.split(':').first: int.parse(entry.split(':').last, radix: 16),
};

/// Every colour that can be written out of one value, for finding them in a
/// declaration.
final RegExp cssColorPattern = RegExp(
  r'#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])'
  r'|(?:rgb|rgba|hsl|hsla)\([^()]*\)'
  r'|(?<![\w#.-])[a-zA-Z]+(?![\w(-])',
);

/// The colour [text] writes, or null if it writes none.
Color? parseCssColor(String text) {
  final value = text.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'transparent') return const Color(0x00000000);
  if (cssNamedColors[value] case final rgb?) return Color(0xFF000000 | rgb);
  if (value.startsWith('#')) return _parseHex(value.substring(1));
  final open = value.indexOf('(');
  if (open < 0 || !value.endsWith(')')) return null;
  final function = value.substring(0, open);
  final parts = value
      .substring(open + 1, value.length - 1)
      .split(RegExp(r'[\s,/]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 3) return null;
  double? component(String part, double scale) {
    if (part.endsWith('%')) {
      final number = double.tryParse(part.substring(0, part.length - 1));
      return number == null ? null : number / 100 * scale;
    }
    return double.tryParse(part);
  }

  final alpha = parts.length > 3 ? component(parts[3], 1) : 1.0;
  if (alpha == null) return null;
  final a = (alpha.clamp(0, 1) * 255).round();
  if (function == 'rgb' || function == 'rgba') {
    final channels = [for (var i = 0; i < 3; i++) component(parts[i], 255)];
    if (channels.contains(null)) return null;
    return Color.fromARGB(
      a,
      channels[0]!.clamp(0, 255).round(),
      channels[1]!.clamp(0, 255).round(),
      channels[2]!.clamp(0, 255).round(),
    );
  }
  if (function == 'hsl' || function == 'hsla') {
    final hue = double.tryParse(parts[0].replaceAll('deg', ''));
    final saturation = component(parts[1], 1);
    final lightness = component(parts[2], 1);
    if (hue == null || saturation == null || lightness == null) return null;
    final s = saturation.clamp(0.0, 1.0);
    final l = lightness.clamp(0.0, 1.0);
    final chroma = (1 - (2 * l - 1).abs()) * s;
    final h = (hue % 360) / 60;
    final x = chroma * (1 - (h % 2 - 1).abs());
    final (r, g, b) = switch (h.floor()) {
      0 => (chroma, x, 0.0),
      1 => (x, chroma, 0.0),
      2 => (0.0, chroma, x),
      3 => (0.0, x, chroma),
      4 => (x, 0.0, chroma),
      _ => (chroma, 0.0, x),
    };
    final m = l - chroma / 2;
    int channel(double v) => ((v + m).clamp(0, 1) * 255).round();
    return Color.fromARGB(a, channel(r), channel(g), channel(b));
  }
  return null;
}

Color? _parseHex(String hex) {
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
  String wide(String short) => short.split('').map((c) => '$c$c').join();
  final full = switch (hex.length) {
    3 || 4 => wide(hex),
    6 || 8 => hex,
    _ => null,
  };
  if (full == null) return null;
  final rgb = int.parse(full.substring(0, 6), radix: 16);
  final alpha = full.length == 8 ? int.parse(full.substring(6), radix: 16) : 255;
  return Color((alpha << 24) | rgb);
}

String _hex2(double channel) =>
    (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');

/// [color] as CSS writes it, in the same notation as [like] where it can be.
String formatCssColor(Color color, {String like = ''}) {
  final opaque = color.a >= 0.999;
  final style = like.trim().toLowerCase();
  if (style.startsWith('rgb') || (!opaque && !style.startsWith('#'))) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    if (opaque) return 'rgb($r, $g, $b)';
    var a = color.a.toStringAsFixed(2);
    if (a.endsWith('0')) a = a.substring(0, a.length - 1);
    return 'rgba($r, $g, $b, $a)';
  }
  final hex = '#${_hex2(color.r)}${_hex2(color.g)}${_hex2(color.b)}';
  return opaque ? hex : '$hex${_hex2(color.a)}';
}
