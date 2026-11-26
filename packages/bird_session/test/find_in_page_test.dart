import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  group('findCountLabel', () {
    String label(String query, int current, int? total) =>
        findCountLabel(query: query, current: current, total: total);

    test('counts from one', () {
      expect(label('a', 0, 5), '1/5');
      expect(label('a', 4, 5), '5/5');
    });

    test('says when there is nothing', () {
      expect(label('zzz', 0, 0), '0/0');
    });

    test('says nothing before there is an answer or a question', () {
      expect(label('a', 0, null), '');
      expect(label('a', 0, -1), '');
      expect(label('', 0, 3), '');
    });

    test('never counts past the total', () {
      expect(label('a', 9, 3), '3/3');
    });
  });

  group('isSamePageForFind', () {
    test('a jump within the page', () {
      expect(isSamePageForFind('https://a.test/x', 'https://a.test/x#part'),
          isTrue);
      expect(
        isSamePageForFind('https://a.test/x#one', 'https://a.test/x#two'),
        isTrue,
      );
      expect(isSamePageForFind('https://a.test/x#', 'https://a.test/x'), isTrue);
    });

    test('another address is another page', () {
      expect(isSamePageForFind('https://a.test/x', 'https://a.test/y'), isFalse);
      expect(
        isSamePageForFind('https://a.test/?v=1', 'https://a.test/?v=2'),
        isFalse,
      );
    });

    test('a route kept after the # is another page', () {
      expect(
        isSamePageForFind('https://a.test/#/inbox', 'https://a.test/#/sent'),
        isFalse,
      );
      expect(
        isSamePageForFind('https://a.test/#!a', 'https://a.test/#!b'),
        isFalse,
      );
    });
  });
}
