/// Gives each keyboard event to one window.
///
/// Flutter calls every keyboard handler for every event, one after another,
/// and each window has its own. Asking only whether a window is the key one is
/// not enough: a shortcut that closes the key window makes another one key on
/// the spot, whose handler then runs for the same event and acts on it too, so
/// that one press of Cmd+W would close a window and then a tab of the next.
class KeyClaims {
  Object? _claimed;

  bool claim(Object event, {required bool Function() isKeyWindow}) {
    if (identical(event, _claimed) || !isKeyWindow()) return false;
    _claimed = event;
    return true;
  }
}
