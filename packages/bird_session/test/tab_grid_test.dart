import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  test('an upright phone has two columns of upright cards', () {
    final grid = TabGridLayout.fit(width: 392, height: 800);
    expect(grid.columns, 2);
    expect(grid.cardWidth, (392 - 24 - 12) / 2);
    expect(grid.cardHeight, greaterThan(grid.cardWidth));
  });

  test('wider screens have more columns, and low ones lower cards', () {
    expect(TabGridLayout.fit(width: 700, height: 900).columns, 3);
    expect(TabGridLayout.fit(width: 1000, height: 1200).columns, 4);
    final sideways = TabGridLayout.fit(width: 500, height: 360);
    expect(sideways.columns, 3);
    expect(sideways.cardHeight, lessThan(sideways.cardWidth));
  });

  test('cards fill rows from the left', () {
    final grid = TabGridLayout.fit(width: 392, height: 800);
    expect(grid.leftOf(0), 12);
    expect(grid.leftOf(1), 12 + grid.cardWidth + 12);
    expect(grid.leftOf(2), 12);
    expect(grid.topOf(1), 12);
    expect(grid.topOf(2), 12 + grid.cardHeight + 12);
    expect(grid.contentHeight(0), 0);
    expect(grid.contentHeight(3), 24 + 2 * grid.cardHeight + 12);
  });

  test('a point belongs to the card nearest it', () {
    final grid = TabGridLayout.fit(width: 392, height: 800);
    for (var index = 0; index < 5; index++) {
      expect(
        grid.indexAt(
          grid.leftOf(index) + grid.cardWidth / 2,
          grid.topOf(index) + grid.cardHeight / 2,
          5,
        ),
        index,
      );
    }
    expect(grid.indexAt(-50, -50, 5), 0);
    expect(grid.indexAt(1000, 5000, 5), 4);
    expect(grid.indexAt(10, 10, 0), 0);
  });

  test('scrolling to a card stays within the content', () {
    final grid = TabGridLayout.fit(width: 392, height: 800);
    expect(grid.scrollOffsetFor(0, 2, 700), 0);
    expect(grid.scrollOffsetFor(0, 20, 700), 0);
    expect(grid.scrollOffsetFor(19, 20, 700), grid.contentHeight(20) - 700);
    expect(grid.scrollOffsetFor(-1, 20, 700), 0);
  });
}
