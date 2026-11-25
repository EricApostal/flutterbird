import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

const screen = ScreenRect(0, 25, 1920, 1055);

void main() {
  test('the first window is in the middle of the screen', () {
    final frame = WindowPlacement.centered(screen);
    expect(frame.size, WindowPlacement.defaultSize);
    expect(frame.center, screen.center);
  });

  test('a new window steps away from the one before and stays on screen', () {
    expect(
      WindowPlacement.cascaded(const ScreenRect(100, 100, 800, 600), screen),
      const ScreenRect(128, 128, 800, 600),
    );
    final atEdge = WindowPlacement.cascaded(
      const ScreenRect(1120, 480, 800, 600),
      screen,
    );
    expect(atEdge.right, lessThanOrEqualTo(screen.right));
    expect(atEdge.bottom, lessThanOrEqualTo(screen.bottom));
  });

  test('a torn off window is as large as its source', () {
    const source = ScreenRect(10, 40, 900, 700);
    expect(WindowPlacement.tearOffSize(source, screen), source.size);
  });

  test('a torn off window does not fill the screen', () {
    final size = WindowPlacement.tearOffSize(screen, screen);
    expect(size.width, lessThan(screen.width));
    expect(size.height, lessThan(screen.height));
  });

  group('popups', () {
    const opener = ScreenRect(200, 100, 1200, 800);

    test('are as large as asked, plus the bar, over the opener', () {
      final frame = WindowPlacement.popup(
        opener: opener,
        screen: screen,
        chromeHeight: 64,
        width: 500,
        height: 600,
      );
      expect(frame.size, const ScreenSize(500, 664));
      expect(frame.center, opener.center);
    });

    test('have a size when the page gives none', () {
      final frame = WindowPlacement.popup(
        opener: opener,
        screen: screen,
        chromeHeight: 64,
        width: 0,
      );
      expect(frame.width, WindowPlacement.defaultPopupSize.width);
      expect(frame.height, WindowPlacement.defaultPopupSize.height + 64);
    });

    test('are neither tiny nor larger than the screen', () {
      final tiny = WindowPlacement.popup(
        opener: opener,
        screen: screen,
        chromeHeight: 64,
        width: 100,
        height: 100,
      );
      expect(tiny.width, WindowPlacement.minimumPopupSize.width);
      expect(tiny.height, WindowPlacement.minimumPopupSize.height + 64);

      final huge = WindowPlacement.popup(
        opener: opener,
        screen: screen,
        chromeHeight: 64,
        width: 9000,
        height: 9000,
      );
      expect(huge, screen);
    });

    test('stay on screen when the opener is at its edge', () {
      final frame = WindowPlacement.popup(
        opener: const ScreenRect(1800, 900, 800, 600),
        screen: screen,
        chromeHeight: 64,
        width: 500,
        height: 600,
      );
      expect(frame.right, lessThanOrEqualTo(screen.right));
      expect(frame.bottom, lessThanOrEqualTo(screen.bottom));
    });
  });
}
