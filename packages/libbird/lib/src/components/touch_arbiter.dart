/// Who a touch belongs to.
///
/// The page is sent every finger's touch, and the browser pans with the same
/// finger. Only one of them may act on it: the page, once it says the touch is
/// its own, as a map being dragged does, and otherwise the browser, which takes
/// the touch back from the page as it starts to pan, as browsers do.
///
/// This only decides. It knows nothing of the engine or of Flutter.
library;

/// How fast a finger was going as it left, in logical pixels a second.
typedef FingerVelocity = ({double x, double y});

/// What the browser is to do next.
class TouchStep {
  const TouchStep({
    this.cancel = const [],
    this.dx = 0,
    this.dy = 0,
    this.fling,
  });

  static const TouchStep nothing = TouchStep();

  /// Fingers to take back from the page, before anything else.
  final List<int> cancel;

  /// How far to pan, as far as the finger moved.
  final double dx;
  final double dy;

  /// Set when the pan is to carry on by itself.
  final FingerVelocity? fling;
}

enum _Owner { undecided, page, browser }

class TouchArbiter {
  _Owner _owner = _Owner.undecided;

  /// The fingers that are down.
  final Set<int> _down = {};

  /// Every finger of the gesture, whose answers are still to be heeded.
  final Set<int> _gesture = {};

  /// The fingers the page has, and is yet to hear the end of.
  final Set<int> _withPage = {};

  // What the browser would do, kept until it knows that it may.
  bool _panning = false;
  double _heldDx = 0;
  double _heldDy = 0;
  FingerVelocity? _heldFling;

  /// Whether the browser wants to pan and is waiting to hear that it may.
  bool get isWaiting => _owner == _Owner.undecided && _panning;

  /// Whether the page has said the gesture is its own.
  bool get isPages => _owner == _Owner.page;

  /// A finger went down. Returns whether the page is to be sent it. A gesture
  /// [forBrowser], as that of a finger put down to stop a page that is still
  /// moving, is none of the page's business.
  bool down(int pointer, {bool forBrowser = false}) {
    if (_down.isEmpty) {
      _owner = forBrowser ? _Owner.browser : _Owner.undecided;
      _gesture.clear();
      _withPage.clear();
      _panning = false;
      _dropHeld();
    }
    _down.add(pointer);
    _gesture.add(pointer);
    if (_owner == _Owner.browser) return false;
    _withPage.add(pointer);
    return true;
  }

  /// Whether the page is to be sent where this finger has moved to.
  bool moves(int pointer) => _withPage.contains(pointer);

  /// A finger left, or was lost. Returns whether the page is to be told.
  bool lift(int pointer) {
    _down.remove(pointer);
    return _withPage.remove(pointer);
  }

  /// What the page made of a step of a finger's touch.
  TouchStep answer(int pointer, {required bool isMove, required bool claimed}) {
    if (!_gesture.contains(pointer)) return TouchStep.nothing;
    if (claimed) {
      // Too late once the browser has taken it.
      if (_owner == _Owner.undecided) {
        _owner = _Owner.page;
        _dropHeld();
      }
      return TouchStep.nothing;
    }
    // A page that lets a finger go down may still keep it as it moves.
    if (isMove && isWaiting) return _takeOver();
    return TouchStep.nothing;
  }

  /// A finger the browser would pan with moved this far.
  TouchStep pan(double dx, double dy) {
    switch (_owner) {
      case _Owner.page:
        return TouchStep.nothing;
      case _Owner.browser:
        return TouchStep(dx: dx, dy: dy);
      case _Owner.undecided:
        _panning = true;
        _heldDx += dx;
        _heldDy += dy;
        return TouchStep.nothing;
    }
  }

  /// The finger left while panning.
  TouchStep panEnd(FingerVelocity velocity) {
    switch (_owner) {
      case _Owner.page:
        return TouchStep.nothing;
      case _Owner.browser:
        return TouchStep(fling: velocity);
      case _Owner.undecided:
        _panning = true;
        _heldFling = velocity;
        return TouchStep.nothing;
    }
  }

  /// The page has taken too long to say, as one busy running a script does, and
  /// is not waited for.
  TouchStep timeOut() => isWaiting ? _takeOver() : TouchStep.nothing;

  /// A finger was held still. Returns null where the gesture is the page's, and
  /// otherwise the fingers to take back before the browser acts on it.
  List<int>? hold() {
    if (_owner == _Owner.page) return null;
    _owner = _Owner.browser;
    return _takeFromPage();
  }

  TouchStep _takeOver() {
    _owner = _Owner.browser;
    final step = TouchStep(
      cancel: _takeFromPage(),
      dx: _heldDx,
      dy: _heldDy,
      fling: _heldFling,
    );
    _dropHeld();
    return step;
  }

  List<int> _takeFromPage() {
    final taken = _withPage.toList();
    _withPage.clear();
    return taken;
  }

  void _dropHeld() {
    _heldDx = 0;
    _heldDy = 0;
    _heldFling = null;
  }
}
