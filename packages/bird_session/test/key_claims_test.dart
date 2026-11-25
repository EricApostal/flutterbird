import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  test(
    'one press is acted on by one window, even as the key window changes',
    () {
      final claims = KeyClaims();
      final press = Object();
      var keyWindow = 1;
      final acted = <int>[];

      // Each window's handler in turn; window 1's closes it, making 2 key.
      for (final window in [1, 2, 3]) {
        if (claims.claim(press, isKeyWindow: () => keyWindow == window)) {
          acted.add(window);
          keyWindow = window + 1;
        }
      }

      expect(acted, [1]);
    },
  );

  test('the next press can be claimed again', () {
    final claims = KeyClaims();
    expect(claims.claim(Object(), isKeyWindow: () => true), isTrue);
    expect(claims.claim(Object(), isKeyWindow: () => true), isTrue);
  });

  test('a window without the keyboard claims nothing', () {
    final claims = KeyClaims();
    final press = Object();
    expect(claims.claim(press, isKeyWindow: () => false), isFalse);
    expect(claims.claim(press, isKeyWindow: () => true), isTrue);
  });
}
