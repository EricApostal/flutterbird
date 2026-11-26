import 'dart:io';

/// Whether the app shows its phone interface: one window, drawn with the
/// widgets under `features/mobile` rather than the desktop's.
bool get usesMobileInterface => Platform.isAndroid || Platform.isIOS;
