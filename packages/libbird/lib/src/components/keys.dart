import 'package:flutter/services.dart';

int getLadybirdKeyCode(LogicalKeyboardKey key) {
  if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
      key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
    return key.keyId - LogicalKeyboardKey.keyA.keyId + 0x41;
  }
  if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
      key.keyId <= LogicalKeyboardKey.digit9.keyId) {
    return key.keyId - LogicalKeyboardKey.digit0.keyId + 0x30;
  }

  // Common keys
  if (key == LogicalKeyboardKey.tab) return 0x09;
  if (key == LogicalKeyboardKey.enter) return 0x0D;
  if (key == LogicalKeyboardKey.space) return 0x20;
  if (key == LogicalKeyboardKey.backspace) return 0x08;
  if (key == LogicalKeyboardKey.escape) return 0x1B;

  // Arrows
  if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
  if (key == LogicalKeyboardKey.arrowUp) return 0x26;
  if (key == LogicalKeyboardKey.arrowRight) return 0x27;
  if (key == LogicalKeyboardKey.arrowDown) return 0x28;

  // Modifiers
  if (key == LogicalKeyboardKey.shiftLeft) return 0x10;
  if (key == LogicalKeyboardKey.shiftRight) return 0xB0;
  if (key == LogicalKeyboardKey.controlLeft) return 0x11;
  if (key == LogicalKeyboardKey.controlRight) return 0xB1;
  if (key == LogicalKeyboardKey.altLeft) return 0x12;
  if (key == LogicalKeyboardKey.altRight) return 0xB2;
  if (key == LogicalKeyboardKey.metaLeft) return 0x92;
  if (key == LogicalKeyboardKey.metaRight) return 0xAC;

  return 0; // Invalid
}

int getModifiersForEvent(Set<LogicalKeyboardKey> pressedKeys) {
  int modifiers = 0;
  for (final key in pressedKeys) {
    if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
      modifiers |= (1 << 0); // Mod_Alt
    }
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
      modifiers |= (1 << 1); // Mod_Ctrl
    }
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      modifiers |= (1 << 2); // Mod_Shift
    }
    if (key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight) {
      modifiers |= (1 << 3); // Mod_Super
    }
  }
  return modifiers;
}
