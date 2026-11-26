/// Where the cards of a phone's tab switcher go.
library;

/// A grid of equal cards, filled left to right and top to bottom. Everything
/// is in logical pixels, from the top left of the scrolled content.
class TabGridLayout {
  const TabGridLayout._({
    required this.columns,
    required this.cardWidth,
    required this.cardHeight,
    required this.padding,
    required this.gap,
  });

  /// The grid for a screen [width] by [height].
  factory TabGridLayout.fit({
    required double width,
    required double height,
    double padding = 12,
    double gap = 12,
  }) {
    final columns = width >= 900 ? 4 : (width >= 560 || width > height ? 3 : 2);
    final cardWidth = ((width - 2 * padding - (columns - 1) * gap) / columns)
        .clamp(1.0, double.infinity);
    // Upright screens get upright cards. A screen on its side is too low for
    // those to be seen whole.
    final cardHeight = width > height ? cardWidth * 0.9 : cardWidth * 1.38;
    return TabGridLayout._(
      columns: columns,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      padding: padding,
      gap: gap,
    );
  }

  final int columns;
  final double cardWidth;
  final double cardHeight;
  final double padding;
  final double gap;

  double leftOf(int index) => padding + (index % columns) * (cardWidth + gap);

  double topOf(int index) => padding + (index ~/ columns) * (cardHeight + gap);

  double contentHeight(int count) {
    if (count <= 0) return 0;
    final rows = (count + columns - 1) ~/ columns;
    return 2 * padding + rows * cardHeight + (rows - 1) * gap;
  }

  /// The place, of [count], whose card is nearest a point: where a card being
  /// dragged with its middle there belongs.
  int indexAt(double x, double y, int count) {
    if (count <= 0) return 0;
    final column = ((x - padding - cardWidth / 2) / (cardWidth + gap))
        .round()
        .clamp(0, columns - 1);
    final lastRow = (count - 1) ~/ columns;
    final row = ((y - padding - cardHeight / 2) / (cardHeight + gap))
        .round()
        .clamp(0, lastRow);
    return (row * columns + column).clamp(0, count - 1);
  }

  /// How far to scroll so that the card at [index] is in the middle of a view
  /// [viewport] high, as far as the content allows.
  double scrollOffsetFor(int index, int count, double viewport) {
    final most = contentHeight(count) - viewport;
    if (most <= 0 || index < 0) return 0;
    final wanted = topOf(index) - (viewport - cardHeight) / 2;
    return wanted.clamp(0.0, most);
  }
}
