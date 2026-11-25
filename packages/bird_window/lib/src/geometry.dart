import 'dart:math' as math;

/// A point, or an offset between two points, in logical points with y down.
final class ScreenPoint {
  const ScreenPoint(this.x, this.y);

  static const ScreenPoint zero = ScreenPoint(0, 0);

  final double x;
  final double y;

  ScreenPoint operator +(ScreenPoint other) =>
      ScreenPoint(x + other.x, y + other.y);

  ScreenPoint operator -(ScreenPoint other) =>
      ScreenPoint(x - other.x, y - other.y);

  @override
  bool operator ==(Object other) =>
      other is ScreenPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ScreenPoint($x, $y)';
}

final class ScreenSize {
  const ScreenSize(this.width, this.height);

  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is ScreenSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ScreenSize($width, $height)';
}

/// A rectangle by its top left corner and size.
final class ScreenRect {
  const ScreenRect(this.left, this.top, this.width, this.height);

  ScreenRect.from(ScreenPoint topLeft, ScreenSize size)
    : this(topLeft.x, topLeft.y, size.width, size.height);

  static const ScreenRect zero = ScreenRect(0, 0, 0, 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  ScreenPoint get topLeft => ScreenPoint(left, top);
  ScreenPoint get center => ScreenPoint(left + width / 2, top + height / 2);
  ScreenSize get size => ScreenSize(width, height);

  bool contains(ScreenPoint point) =>
      point.x >= left && point.x < right && point.y >= top && point.y < bottom;

  /// This rectangle grown by [amount] on every side.
  ScreenRect inflate(double amount) => ScreenRect(
    left - amount,
    top - amount,
    width + amount * 2,
    height + amount * 2,
  );

  ScreenRect translate(ScreenPoint by) =>
      ScreenRect(left + by.x, top + by.y, width, height);

  ScreenRect moveTo(ScreenPoint topLeft) =>
      ScreenRect(topLeft.x, topLeft.y, width, height);

  /// This rectangle shrunk to fit in [area] if it is larger, then moved the
  /// least distance that puts all of it inside.
  ScreenRect keepInside(ScreenRect area) {
    final w = math.min(width, area.width);
    final h = math.min(height, area.height);
    return ScreenRect(
      left.clamp(area.left, area.right - w).toDouble(),
      top.clamp(area.top, area.bottom - h).toDouble(),
      w,
      h,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'ScreenRect($left, $top, $width x $height)';
}
