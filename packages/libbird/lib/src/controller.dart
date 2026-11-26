import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter/services.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';
import 'package:ladybird/src/models/context_menu.dart';
import 'package:ladybird/src/models/context_menu_target.dart';
import 'package:ladybird/src/models/download.dart';
import 'package:ladybird/src/models/session_history.dart';
import 'package:ladybird/src/models/settings.dart';
import 'dart:ui' as ui;

ffi.DynamicLibrary _openLadybirdLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libengine.so');
  }
  return ffi.DynamicLibrary.process();
}

/// A view the engine made for a page: a link that opens a new tab, or
/// `window.open`. The page that asked stays its opener, so it has to be shown
/// through this view; a view of the app's own at the same address would not do.
class LadybirdNewWebViewRequest {
  const LadybirdNewWebViewRequest({
    required this.viewId,
    required this.activate,
    this.isPopup = false,
    this.left,
    this.top,
    this.width,
    this.height,
  });

  // Mirrors LadybirdWindowFeature in cpp/engine.h.
  static const int _popup = 1 << 0;
  static const int _hasX = 1 << 1;
  static const int _hasY = 1 << 2;
  static const int _hasWidth = 1 << 3;
  static const int _hasHeight = 1 << 4;

  factory LadybirdNewWebViewRequest.fromNative(
    int viewId,
    bool activate,
    int features,
    int x,
    int y,
    int width,
    int height,
  ) => LadybirdNewWebViewRequest(
    viewId: viewId,
    activate: activate,
    isPopup: features & _popup != 0,
    left: features & _hasX != 0 ? x : null,
    top: features & _hasY != 0 ? y : null,
    width: features & _hasWidth != 0 ? width : null,
    height: features & _hasHeight != 0 ? height : null,
  );

  final int viewId;

  /// Whether to show the new view rather than open it in the background.
  final bool activate;

  /// Whether a popup window was asked for, rather than a tab.
  final bool isPopup;

  /// Where on screen and how large the page asked to be, in CSS pixels. The
  /// size is that of the page itself, without any window around it.
  final int? left;
  final int? top;
  final int? width;
  final int? height;
}

class LadybirdController {
  /// What a view is paced at where the engine cannot follow a display (see
  /// [followDisplay]).
  static const double assumedRefreshRate = 512.0;
  static final bool _pacesByDisplay = Platform.isMacOS;
  static ({int id, double refreshRate})? _lastDisplay;
  ({int id, double refreshRate})? _display;

  final MethodChannel _channel = MethodChannel('ladybird');
  late final LadybirdBindings _bindings;
  // int? _textureId;
  Size? _lastSize;
  double? _lastDevicePixelRatio;
  late final int _viewId;
  // When null, the initial navigation goes to [newTabUrl].
  final String? initialUrl;
  bool hasNavigatedInitial = false;
  bool _lastFocused = false;
  bool hasStartedNavigation = false;

  /// The address last asked for through [navigate].
  String? _requestedUrl;

  late final ffi.NativeCallable<ffi.Void Function()> _resizeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>
  _urlChangeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>
  _titleChangeCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int)
  >
  _faviconChangeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Int)>
  _crossSiteNavigationCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Bool)>
  _loadingStateChangeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Int)>
  _cursorChangeCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>)
  >
  _contextMenuRequestCallback;
  late final ffi.NativeCallable<NewWebViewCallbackFunction> _newWebViewCallback;
  late final ffi.NativeCallable<CloseViewCallbackFunction> _closeViewCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Int, ffi.Bool, ffi.Int, ffi.Int, ffi.Int, ffi.Int)
  >
  _inputCaretRectChangeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Int, ffi.Bool)>
  _fullscreenChangeCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>)
  >
  _navigationHistoryChangeCallback;

  static ffi.NativeCallable<DisplayDownloadConfirmationDialogCallbackFunction>?
  _displayDownloadConfirmationDialogCallback;
  static ffi.NativeCallable<DisplayErrorDialogCallbackFunction>?
  _displayErrorDialogCallback;
  static ffi.NativeCallable<SetClipboardTextCallbackFunction>?
  _setClipboardTextCallback;
  static ffi.NativeCallable<DownloadUpdateCallbackFunction>?
  _downloadUpdateCallback;
  static ffi.NativeCallable<DownloadRemovedCallbackFunction>?
  _downloadRemovedCallback;

  static String? Function(String)? onAskUserForDownloadPath;
  static void Function(String, String)? onDisplayDownloadConfirmationDialog;
  static void Function(String)? onDisplayErrorDialog;

  // Downloads are process-global (tracked by a single WebView::FileDownloader
  // in the engine), not per-tab, so this lives on the class rather than on an
  // instance. Newest downloads are kept first.
  static final ValueNotifier<List<LadybirdDownload>> downloadsNotifier =
      ValueNotifier(const []);
  static bool _downloadsSeeded = false;

  // Holds the text the synchronous GetClipboardTextCallback (invoked mid-paste,
  // on the same isolate) hands back, since nothing can await the real OS
  // clipboard from inside that callback. Refreshed before anything that lets
  // the engine read the clipboard -- pasteFromClipboard() and every context menu
  // action, whose "Paste" entry is the engine's own.
  static String? _pendingPasteText;

  void Function()? onResize;
  final Set<VoidCallback> _resizeListeners = <VoidCallback>{};
  void Function()? onCrossSiteNavigation;
  void Function(LadybirdContextMenuRequest request)? onContextMenuRequest;

  /// What the menu last passed to [onContextMenuRequest] was asked for on.
  LadybirdContextMenuTarget get contextMenuTarget => _contextMenuTarget;
  LadybirdContextMenuTarget _contextMenuTarget =
      const LadybirdContextMenuTarget();

  /// Set by whoever keeps the app's tabs. A view that has none of its own,
  /// such as an extension's popup, falls back to [fallbackNewWebViewHandler].
  void Function(LadybirdNewWebViewRequest request)? onNewWebView;

  /// Takes the views asked for by a view with no [onNewWebView]. Without it
  /// such a view would be made by the engine and never shown.
  static void Function(LadybirdNewWebViewRequest request)?
  fallbackNewWebViewHandler;

  /// Fired when the page closes itself, as with `window.close()`. The view has
  /// nothing more to show, and its owner should [dispose] it.
  void Function()? get onCloseRequested => _onCloseRequested;
  set onCloseRequested(void Function()? handler) {
    _onCloseRequested = handler;
    // The page can close before anyone is listening.
    if (handler != null && _closedByPage) scheduleMicrotask(handler);
  }

  void Function()? _onCloseRequested;
  bool _closedByPage = false;
  // Fired when the page enters/exits fullscreen via the DOM Fullscreen API
  // (e.g. a <video>'s native fullscreen control), not by any user action in
  // the Flutter chrome.
  void Function(bool isFullscreen)? onFullscreenChange;

  final ValueNotifier<String> urlNotifier = ValueNotifier("");
  final ValueNotifier<String> titleNotifier = ValueNotifier("Tab");
  final ValueNotifier<dynamic> faviconNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> canGoBackNotifier = ValueNotifier(false);
  final ValueNotifier<bool> canGoForwardNotifier = ValueNotifier(false);
  // Ladybird's own session history mirror for this tab -- the authoritative
  // back/forward stack, refreshed for any cause of change (link tap, typed
  // URL, JS navigation, pushState/replaceState, back/forward traversal,
  // reload). Never reconstructed client-side.
  final ValueNotifier<List<LadybirdSessionHistoryEntry>>
  sessionHistoryNotifier = ValueNotifier(const []);
  final ValueNotifier<MouseCursor> mouseCursorNotifier = ValueNotifier(
    SystemMouseCursors.basic,
  );
  // The device-pixel caret rect of the currently-focused editable element, or
  // null when no editable element is focused. Embedders (LadybirdView) use the
  // null <-> non-null transition to attach/detach a platform soft keyboard.
  final ValueNotifier<ui.Rect?> inputCaretRectNotifier = ValueNotifier(null);

  int get viewId => _viewId;

  LadybirdController({this.initialUrl}) {
    _bindings = LadybirdBindings(_openLadybirdLibrary());
    _initialize();
  }

  LadybirdController.fromExistingViewId({
    required int viewId,
    this.initialUrl,
  }) {
    _bindings = LadybirdBindings(_openLadybirdLibrary());
    _initialize(existingViewId: viewId);
  }

  void addResizeListener(VoidCallback listener) {
    _resizeListeners.add(listener);
  }

  void removeResizeListener(VoidCallback listener) {
    _resizeListeners.remove(listener);
  }

  void _initialize({int? existingViewId}) {
    if (_displayErrorDialogCallback == null) {
      _bindings.set_ask_user_for_download_path_callback(
        ffi.Pointer.fromFunction(_onAskUserForDownloadPath),
      );

      _displayDownloadConfirmationDialogCallback =
          ffi.NativeCallable<
            DisplayDownloadConfirmationDialogCallbackFunction
          >.listener(_onDisplayDownloadConfirmationDialog);
      _bindings.set_display_download_confirmation_dialog_callback(
        _displayDownloadConfirmationDialogCallback!.nativeFunction,
      );

      _displayErrorDialogCallback =
          ffi.NativeCallable<DisplayErrorDialogCallbackFunction>.listener(
            _onDisplayErrorDialog,
          );
      _bindings.set_display_error_dialog_callback(
        _displayErrorDialogCallback!.nativeFunction,
      );

      // The engine has no access to the real OS clipboard, so it asks the
      // Flutter host for clipboard text via this callback. It's invoked
      // synchronously mid-paste, so we can't await Clipboard.getData here;
      // pasteFromClipboard() pre-fetches the text and caches it below.
      _bindings.set_get_clipboard_text_callback(
        ffi.Pointer.fromFunction(_onGetClipboardText),
      );

      _setClipboardTextCallback =
          ffi.NativeCallable<SetClipboardTextCallbackFunction>.listener(
            _onSetClipboardText,
          );
      _bindings.set_set_clipboard_text_callback(
        _setClipboardTextCallback!.nativeFunction,
      );

      _downloadUpdateCallback =
          ffi.NativeCallable<DownloadUpdateCallbackFunction>.listener(
            _onDownloadUpdate,
          );
      _bindings.set_download_update_callback(
        _downloadUpdateCallback!.nativeFunction,
      );

      _downloadRemovedCallback =
          ffi.NativeCallable<DownloadRemovedCallbackFunction>.listener(
            _onDownloadRemoved,
          );
      _bindings.set_download_removed_callback(
        _downloadRemovedCallback!.nativeFunction,
      );
    }

    _bindings.init_ladybird();

    if (!_downloadsSeeded) {
      _downloadsSeeded = true;
      _seedDownloadsFromEngine();
    }

    _viewId = existingViewId ?? _bindings.create_web_view();
    if (existingViewId != null) {
      // This view is already created and navigated by the native on_new_web_view
      // flow, so do not run Flutter's default initial-url navigation.
      hasNavigatedInitial = true;
      hasStartedNavigation = true;
    }

    _resizeCallback = ffi.NativeCallable<ffi.Void Function()>.listener(
      _onResize,
    );
    _bindings.set_resize_callback(_viewId, _resizeCallback.nativeFunction);

    _urlChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>.listener(
          _onUrlChange,
        );
    _bindings.set_url_change_callback(
      _viewId,
      _urlChangeCallback.nativeFunction,
    );

    _titleChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>.listener(
          _onTitleChange,
        );
    _bindings.set_title_change_callback(
      _viewId,
      _titleChangeCallback.nativeFunction,
    );

    _faviconChangeCallback =
        ffi.NativeCallable<
          ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int)
        >.listener(_onFaviconChange);
    _bindings.set_favicon_change_callback(
      _viewId,
      _faviconChangeCallback.nativeFunction,
    );

    _crossSiteNavigationCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Int)>.listener(
          _onCrossSiteNavigation,
        );
    _bindings.set_cross_site_navigation_callback(
      _viewId,
      _crossSiteNavigationCallback.nativeFunction,
    );

    _loadingStateChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Bool)>.listener(
          _onLoadingStateChange,
        );
    _bindings.set_loading_state_change_callback(
      _viewId,
      _loadingStateChangeCallback.nativeFunction,
    );

    _cursorChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Int)>.listener(
          _onCursorChange,
        );
    _bindings.set_cursor_change_callback(
      _viewId,
      _cursorChangeCallback.nativeFunction,
    );

    _contextMenuRequestCallback =
        ffi.NativeCallable<
          ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>)
        >.listener(_onContextMenuRequest);
    _bindings.set_context_menu_request_callback(
      _viewId,
      _contextMenuRequestCallback.nativeFunction,
    );

    _newWebViewCallback =
        ffi.NativeCallable<NewWebViewCallbackFunction>.listener(_onNewWebView);
    _bindings.set_new_web_view_callback(
      _viewId,
      _newWebViewCallback.nativeFunction,
    );

    _closeViewCallback = ffi.NativeCallable<CloseViewCallbackFunction>.listener(
      _onCloseView,
    );
    _bindings.set_close_view_callback(
      _viewId,
      _closeViewCallback.nativeFunction,
    );

    _inputCaretRectChangeCallback =
        ffi.NativeCallable<
          ffi.Void Function(
            ffi.Int,
            ffi.Bool,
            ffi.Int,
            ffi.Int,
            ffi.Int,
            ffi.Int,
          )
        >.listener(_onInputCaretRectChange);
    _bindings.set_input_caret_rect_change_callback(
      _viewId,
      _inputCaretRectChangeCallback.nativeFunction,
    );

    _fullscreenChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Int, ffi.Bool)>.listener(
          _onFullscreenChange,
        );
    _bindings.set_fullscreen_change_callback(
      _viewId,
      _fullscreenChangeCallback.nativeFunction,
    );

    _navigationHistoryChangeCallback =
        ffi.NativeCallable<
          ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>)
        >.listener(_onNavigationHistoryChange);
    _bindings.set_navigation_history_change_callback(
      _viewId,
      _navigationHistoryChangeCallback.nativeFunction,
    );

    if (existingViewId != null) {
      syncUrlFromEngine();
    }

    _refreshNavigationState();
    _initializeDisplayPacing();

    // _bindings.set_zoom(_viewId, 1.0);
    // _lastDevicePixelRatio = 1.0;
  }

  void _onUrlChange(ffi.Pointer<ffi.Char> urlPointer) {
    if (urlPointer != ffi.nullptr) {
      final url = urlPointer.cast<Utf8>().toDartString();
      if (url == ':') {
        malloc.free(urlPointer);
        return;
      }
      urlNotifier.value = url;
      _refreshNavigationState();
      malloc.free(urlPointer);
    }
  }

  void _onTitleChange(ffi.Pointer<ffi.Char> titlePointer) {
    if (titlePointer != ffi.nullptr) {
      final title = titlePointer.cast<Utf8>().toDartString();
      titleNotifier.value = title;
      malloc.free(titlePointer);
    }
  }

  void _onFaviconChange(
    ffi.Pointer<ffi.Uint8> dataPointer,
    int width,
    int height,
  ) {
    if (dataPointer != ffi.nullptr) {
      if (width > 0 && height > 0) {
        final length = width * height * 4;
        final bgraBytes = dataPointer.asTypedList(length);
        final rgbaBytes = Uint8List(length);
        for (int i = 0; i < length; i += 4) {
          rgbaBytes[i] = bgraBytes[i + 2]; // R
          rgbaBytes[i + 1] = bgraBytes[i + 1]; // G
          rgbaBytes[i + 2] = bgraBytes[i]; // B
          rgbaBytes[i + 3] = bgraBytes[i + 3]; // A
        }

        ui.decodeImageFromPixels(
          rgbaBytes,
          width,
          height,
          ui.PixelFormat.rgba8888,
          (image) {
            faviconNotifier.value = image;
          },
        );
      }
      malloc.free(dataPointer);
    }
  }

  void _onResize() {
    onResize?.call();
    for (final listener in _resizeListeners.toList(growable: false)) {
      listener();
    }
  }

  void _onCrossSiteNavigation(int viewId) {
    if (viewId != _viewId) return;
    onCrossSiteNavigation?.call();
  }

  void _onLoadingStateChange(bool isLoading) {
    isLoadingNotifier.value = isLoading;
    _refreshNavigationState();
  }

  void _onCursorChange(int cursorType) {
    final nextCursor = _mapNativeCursor(cursorType);
    if (mouseCursorNotifier.value != nextCursor) {
      mouseCursorNotifier.value = nextCursor;
    }
  }

  void _onContextMenuRequest(int viewId, ffi.Pointer<ffi.Char> menuJson) {
    if (menuJson == ffi.nullptr) return;

    try {
      if (viewId != _viewId) return;

      final jsonString = menuJson.cast<Utf8>().toDartString();
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return;

      final map = Map<String, dynamic>.from(decoded);
      final request = LadybirdContextMenuRequestMapper.fromMap(map);
      _contextMenuTarget = LadybirdContextMenuTarget.fromMap(map);
      onContextMenuRequest?.call(request);
    } finally {
      malloc.free(menuJson);
    }
  }

  void _onNewWebView(
    int newViewId,
    bool activateTab,
    int features,
    int x,
    int y,
    int width,
    int height,
  ) {
    if (newViewId <= 0) return;
    (onNewWebView ?? fallbackNewWebViewHandler)?.call(
      LadybirdNewWebViewRequest.fromNative(
        newViewId,
        activateTab,
        features,
        x,
        y,
        width,
        height,
      ),
    );
  }

  void _onCloseView(int viewId) {
    if (viewId != _viewId || _closedByPage) return;
    _closedByPage = true;
    _onCloseRequested?.call();
  }

  void _onNavigationHistoryChange(
    int viewId,
    ffi.Pointer<ffi.Char> historyJson,
  ) {
    if (historyJson == ffi.nullptr) return;

    try {
      if (viewId != _viewId) return;

      final jsonString = historyJson.cast<Utf8>().toDartString();
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return;

      sessionHistoryNotifier.value = decoded
          .whereType<Map<String, dynamic>>()
          .map(LadybirdSessionHistoryEntryMapper.fromMap)
          .toList();
    } finally {
      malloc.free(historyJson);
    }
  }

  void _onFullscreenChange(int viewId, bool isFullscreen) {
    print(
      '[Fullscreen] native callback viewId=$viewId isFullscreen=$isFullscreen '
      '(this._viewId=$_viewId)',
    );
    if (viewId != _viewId) return;
    onFullscreenChange?.call(isFullscreen);
  }

  // Asks the page's fullscreen element (if any) to exit fullscreen. Used for
  // platform-level exit gestures (e.g. Android back) that aren't a key event
  // the engine already handles itself (like Escape).
  void requestExitFullscreen() {
    print('[Fullscreen] requestExitFullscreen viewId=$_viewId');
    _bindings.request_exit_fullscreen(_viewId);
  }

  // Tells the engine we've *settled* into (or out of) fullscreen — call only
  // after the host's own platform-level transition (OS window fullscreen,
  // immersive mode, etc) has actually finished, not immediately on
  // [onFullscreenChange] firing. This unblocks the DOM Fullscreen API's
  // pending enter/exit operation on the engine side.
  void confirmFullscreenState(bool isFullscreen) {
    print(
      '[Fullscreen] confirmFullscreenState viewId=$_viewId '
      'isFullscreen=$isFullscreen',
    );
    _bindings.confirm_fullscreen_state(_viewId, isFullscreen);
  }

  void _onInputCaretRectChange(
    int viewId,
    bool hasRect,
    int x,
    int y,
    int width,
    int height,
  ) {
    if (viewId != _viewId) return;
    inputCaretRectNotifier.value = hasRect
        ? ui.Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            width.toDouble(),
            height.toDouble(),
          )
        : null;
  }

  void syncUrlFromEngine() {
    final ptr = _bindings.get_view_url(_viewId);
    if (ptr == ffi.nullptr) return;

    final url = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    if (url.isEmpty || url == ':') return;
    if (urlNotifier.value == url) return;

    urlNotifier.value = url;
    _refreshNavigationState();
  }

  MouseCursor _mapNativeCursor(int cursorType) {
    switch (cursorType) {
      case 0: // None
      case 1: // Hidden
        return SystemMouseCursors.none;
      case 2: // Arrow
        return SystemMouseCursors.basic;
      case 3: // Crosshair
        return SystemMouseCursors.precise;
      case 4: // IBeam
        return SystemMouseCursors.text;
      case 5: // ResizeHorizontal
        return SystemMouseCursors.resizeLeftRight;
      case 6: // ResizeVertical
        return SystemMouseCursors.resizeUpDown;
      case 7: // ResizeDiagonalTLBR
        return SystemMouseCursors.resizeUpLeftDownRight;
      case 8: // ResizeDiagonalBLTR
        return SystemMouseCursors.resizeUpRightDownLeft;
      case 9: // ResizeColumn
        return SystemMouseCursors.resizeColumn;
      case 10: // ResizeRow
        return SystemMouseCursors.resizeRow;
      case 11: // Hand
        return SystemMouseCursors.click;
      case 12: // Help
        return SystemMouseCursors.help;
      case 13: // OpenHand
        return SystemMouseCursors.grab;
      case 14: // Drag
        return SystemMouseCursors.grabbing;
      case 15: // DragCopy
        return SystemMouseCursors.copy;
      case 16: // Move
        return SystemMouseCursors.move;
      case 17: // Wait
        return SystemMouseCursors.progress;
      case 18: // Disallowed
        return SystemMouseCursors.forbidden;
      case 19: // Eyedropper
        return SystemMouseCursors.precise;
      case 20: // Zoom
        return SystemMouseCursors.zoomIn;
      default:
        return SystemMouseCursors.basic;
    }
  }

  void _refreshNavigationState() {
    canGoBackNotifier.value = _bindings.can_go_back(_viewId);
    canGoForwardNotifier.value = _bindings.can_go_forward(_viewId);
  }

  void navigate(String url) {
    String parsedUrl = url;
    hasStartedNavigation = true;
    _requestedUrl = url;
    print("navigating to url: $url");
    // todo: more reliable system for other formats, such as file://
    // if (!url.startsWith("http")) {
    //   parsedUrl = "https://$url";
    // }
    final ffi.Pointer<Utf8> charPointer = parsedUrl.toNativeUtf8();
    _bindings.navigate_to(_viewId, charPointer.cast<ffi.Char>());
    malloc.free(charPointer);
    _refreshNavigationState();
  }

  void updateDevicePixelRatio(double ratio) {
    if (ratio <= 0) return;
    if (_lastDevicePixelRatio == ratio) return;
    print("[LibBird] Controller.updateDevicePixelRatio: ratio=$ratio");
    _lastDevicePixelRatio = ratio;
    _bindings.set_zoom(_viewId, ratio);
  }

  Brightness? _lastBrightness;

  // Mirrors the host's light/dark theme into the page so
  // `prefers-color-scheme` media queries resolve correctly. Values match
  // Web::CSS::PreferredColorScheme (0 = Auto, 1 = Dark, 2 = Light).
  void updateColorScheme(Brightness brightness) {
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    final colorScheme = brightness == Brightness.dark ? 1 : 2;
    _bindings.set_preferred_color_scheme(_viewId, colorScheme);
  }

  void reload() {
    _bindings.reload_tab(_viewId);
    _refreshNavigationState();
  }

  void goBack() {
    _bindings.go_back(_viewId);
    _refreshNavigationState();
  }

  void goForward() {
    _bindings.go_forward(_viewId);
    _refreshNavigationState();
  }

  bool canGoBack() {
    return canGoBackNotifier.value;
  }

  bool canGoForward() {
    return canGoForwardNotifier.value;
  }

  bool isLoading() {
    return _bindings.is_tab_loading(_viewId);
  }

  String? _profileConfigDirectory;

  /// The profile's config directory, where per-profile files such as the
  /// embedder's bookmarks live. The engine's profile does not move, so this is
  /// read once.
  String? getProfileConfigDirectory() {
    if (_profileConfigDirectory != null) return _profileConfigDirectory;
    final ptr = _bindings.get_profile_config_directory();
    if (ptr == ffi.nullptr) return null;
    _profileConfigDirectory = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return _profileConfigDirectory;
  }

  /// The current page's favicon hash, or null when it has none.
  String? getViewFaviconHash() {
    final ptr = _bindings.get_view_favicon_hash(_viewId);
    if (ptr == ffi.nullptr) return null;
    final hash = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return hash;
  }

  /// The PNG of a favicon the engine has stored, base64-encoded, or null when
  /// it has none.
  String? getFaviconPngBase64(String hash) {
    final hashPtr = hash.toNativeUtf8();
    final ptr = _bindings.get_favicon_png_base64(hashPtr.cast<ffi.Char>());
    malloc.free(hashPtr);
    if (ptr == ffi.nullptr) return null;
    final encoded = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return encoded;
  }

  String getHistoryAutocompleteJson(String query, {int limit = 8}) {
    final queryPtr = query.toNativeUtf8();
    final ptr = _bindings.history_autocomplete_json(
      _viewId,
      queryPtr.cast<ffi.Char>(),
      limit,
    );
    malloc.free(queryPtr);
    if (ptr == ffi.nullptr) return '[]';
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return json;
  }

  // Returns every search engine the engine knows about -- its builtins plus
  // any custom engines (name + query URL template), in that order.
  List<LadybirdSearchEngine> getSearchEngines() => searchEngines();

  /// Every search engine the engine knows about, as [getSearchEngines] does,
  /// through the process-wide bindings: the list is engine state, not a tab's.
  static List<LadybirdSearchEngine> searchEngines() {
    final ptr = _staticBindings.get_search_engines_json();
    if (ptr == ffi.nullptr) return const [];
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LadybirdSearchEngineMapper.fromMap)
        .toList();
  }

  // Returns the name of the currently configured search engine, or null if
  // none has been explicitly configured. The engine itself has no implicit
  // default in that case (see WebView::sanitize_url) — callers should fall
  // back to a search engine of their choosing, e.g. via [activeSearchEngine].
  String? getSearchEngineName() => searchEngineName();

  /// The configured search engine's name, as [getSearchEngineName] gives it,
  /// through the process-wide bindings: it is engine state, not a tab's.
  static String? searchEngineName() {
    final ptr = _staticBindings.get_search_engine_name();
    if (ptr == ffi.nullptr) return null;
    final name = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return name;
  }

  // Sets the active search engine by name. Pass null to clear the selection
  // and fall back to [fallbackSearchEngine]. Throws [ArgumentError] if no
  // engine by that name exists -- the engine refuses an unknown name rather
  // than silently dropping the selection, so a typo can't look like success.
  void setSearchEngine(String? name) => selectSearchEngine(name);

  /// Sets the active search engine, as [setSearchEngine] does, for the whole
  /// process.
  static void selectSearchEngine(String? name) {
    if (name == null || name.isEmpty) {
      _staticBindings.set_search_engine(ffi.nullptr);
      return;
    }
    final namePtr = name.toNativeUtf8();
    final didSet = _staticBindings.set_search_engine(namePtr.cast<ffi.Char>());
    malloc.free(namePtr);
    if (!didSet) {
      throw ArgumentError('No search engine named "$name" is known.');
    }
  }

  // Adds a custom search engine and makes it the active one. [queryUrl] is the
  // engine's query template, e.g. "https://example.com/search?q=%s".
  //
  // Throws [ArgumentError] with a message worth showing the user if the name is
  // empty or already taken, or if the URL isn't one the engine accepts (a valid
  // absolute URL containing "%s").
  void addCustomSearchEngine(String name, String queryUrl) =>
      addNewSearchEngine(name, queryUrl);

  /// Adds a custom search engine and selects it, as [addCustomSearchEngine]
  /// does, for the whole process.
  static void addNewSearchEngine(String name, String queryUrl) {
    final newName = name.trim();
    final newQueryUrl = queryUrl.trim();

    if (newName.isEmpty) {
      throw ArgumentError('A search engine needs a name.');
    }
    if (newQueryUrl.isEmpty) {
      throw ArgumentError('A search engine needs a search URL.');
    }
    if (!newQueryUrl.contains('%s')) {
      throw ArgumentError(
        'The search URL must contain "%s" where the query goes, '
        'e.g. "https://example.com/search?q=%s".',
      );
    }
    if (searchEngines().any((engine) => engine.name == newName)) {
      throw ArgumentError('A search engine named "$newName" already exists.');
    }

    final namePtr = newName.toNativeUtf8();
    final queryUrlPtr = newQueryUrl.toNativeUtf8();
    final didAdd = _staticBindings.add_custom_search_engine(
      namePtr.cast<ffi.Char>(),
      queryUrlPtr.cast<ffi.Char>(),
    );
    malloc.free(namePtr);
    malloc.free(queryUrlPtr);

    if (!didAdd) {
      throw ArgumentError(
        '"$newQueryUrl" is not a search URL the engine accepts; it must be a '
        'valid URL containing "%s".',
      );
    }
    selectSearchEngine(newName);
  }

  // Used when no search engine has been explicitly configured.
  static const LadybirdSearchEngine fallbackSearchEngine = LadybirdSearchEngine(
    name: 'DuckDuckGo',
    queryUrl: 'https://duckduckgo.com/?q=%s',
  );

  // Resolves the search engine that should currently be used for queries:
  // the configured engine if it's still a known builtin/custom engine,
  // otherwise [fallbackSearchEngine].
  LadybirdSearchEngine get activeSearchEngine {
    final engines = getSearchEngines();
    final wantedName = getSearchEngineName() ?? fallbackSearchEngine.name;

    for (final engine in engines) {
      if (engine.name == wantedName) return engine;
    }
    return engines.isNotEmpty ? engines.first : fallbackSearchEngine;
  }

  /// What a new tab opens: the app shows its own page over the engine's plain
  /// one at this address.
  String get newTabUrl => 'about:newtab';

  /// Whether the tab is on the new tab page, or is on its way there as a tab
  /// that has only just opened.
  bool get isOnNewTabPage {
    final url = urlNotifier.value.trim();
    if (url == 'about:newtab') return true;
    // Before the engine reports an address, and while it is still on the empty
    // document every view starts with.
    if (url.isNotEmpty && url != 'about:blank') return false;
    final requested = _requestedUrl;
    if (requested != null) return requested == 'about:newtab';
    return !hasStartedNavigation && initialUrl == null;
  }

  /// Whether the tab is on the app's settings page, which is drawn over the
  /// engine's own page at this address, or is on its way there.
  bool get isOnSettingsPage {
    // Only the desktop has a page of the app's own to show.
    if (Platform.isAndroid || Platform.isIOS) return false;
    final url = urlNotifier.value.trim();
    if (_isSettingsUrl(url)) return true;
    // Before the engine reports an address, and while it is still on the empty
    // document every view starts with.
    if (url.isNotEmpty && url != 'about:blank') return false;
    final requested = _requestedUrl ?? initialUrl;
    return requested != null && _isSettingsUrl(requested);
  }

  static bool _isSettingsUrl(String url) =>
      url == 'about:settings' || url.startsWith('about:settings#');

  // The front page of the active search engine, e.g.
  // "https://duckduckgo.com/".
  String get homeUrl {
    final host = Uri.tryParse(activeSearchEngine.queryUrl)?.host;
    return host != null && host.isNotEmpty
        ? 'https://$host/'
        : 'https://duckduckgo.com/';
  }

  // Returns the schema (name/title/description/default value) for every
  // generic engine config variable, so new settings surfaced by the engine
  // don't require new bindings to be discoverable.
  List<LadybirdConfigVariableDefinition> getConfigVariableDefinitions() =>
      configVariableDefinitions();

  // Returns the current value of a config variable by name, or null if the
  // name isn't recognized by the engine.
  dynamic getConfigVariable(String name) => configVariable(name);

  // Sets a config variable by name. Returns false if the name isn't
  // recognized by the engine (invalid values for a known variable are
  // silently ignored, matching engine behavior).
  bool setConfigVariable(String name, Object? value) =>
      setConfigVariableValue(name, value);

  // Returns a full snapshot of every engine setting (search engine, tab
  // settings, zoom, languages, browsing behavior, autoplay, etc), as defined
  // by WebView::Settings::serialize_json().
  Map<String, dynamic> getSettingsJson() => settingsSnapshot();

  // Engine settings are process-global, like downloads, so these read and
  // write them through one shared bindings handle rather than a tab's.
  static List<LadybirdConfigVariableDefinition> configVariableDefinitions() {
    final ptr = _staticBindings.get_config_variable_definitions_json();
    if (ptr == ffi.nullptr) return const [];
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(LadybirdConfigVariableDefinitionMapper.fromMap)
        .toList();
  }

  static dynamic configVariable(String name) {
    final namePtr = name.toNativeUtf8();
    final ptr = _staticBindings.get_config_variable_json(namePtr.cast<ffi.Char>());
    malloc.free(namePtr);
    if (ptr == ffi.nullptr) return null;

    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return jsonDecode(json);
  }

  static bool setConfigVariableValue(String name, Object? value) {
    final namePtr = name.toNativeUtf8();
    final valuePtr = jsonEncode(value).toNativeUtf8();
    final result = _staticBindings.set_config_variable_json(
      namePtr.cast<ffi.Char>(),
      valuePtr.cast<ffi.Char>(),
    );
    malloc.free(namePtr);
    malloc.free(valuePtr);
    return result;
  }

  /// The engine's settings as they are now, or an empty map when the engine
  /// has not started yet.
  static Map<String, dynamic> settingsSnapshot() {
    final ptr = _staticBindings.get_settings_json();
    if (ptr == ffi.nullptr) return const {};
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return const {};
    return decoded;
  }

  /// Applies a partial snapshot to the engine's settings and saves them: maps
  /// merge into the ones they name, and a null removes a key. Returns whether
  /// the engine took the change.
  static bool applySettingsChanges(Map<String, Object?> changes) {
    final jsonPtr = jsonEncode(changes).toNativeUtf8();
    final applied = _staticBindings.apply_settings_json(
      jsonPtr.cast<ffi.Char>(),
    );
    malloc.free(jsonPtr);
    return applied;
  }

  /// Removes a custom search engine by name. Builtin engines and unknown
  /// names change nothing. Removing the selected engine clears the selection.
  static bool removeCustomSearchEngine(String name) {
    final namePtr = name.toNativeUtf8();
    final removed = _staticBindings.remove_custom_search_engine(
      namePtr.cast<ffi.Char>(),
    );
    malloc.free(namePtr);
    return removed;
  }

  void _seedDownloadsFromEngine() {
    final ptr = _bindings.get_downloads_json();
    if (ptr == ffi.nullptr) return;
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    final decoded = jsonDecode(json);
    if (decoded is! List) return;
    downloadsNotifier.value = decoded
        .whereType<Map<String, dynamic>>()
        .map(LadybirdDownloadMapper.fromMap)
        .toList();
  }

  // Downloads are process-global engine state, not tied to any one tab/view,
  // so these are static and share a single bindings handle rather than
  // requiring (and wastefully constructing) a per-tab LadybirdController.
  static final LadybirdBindings _staticBindings = LadybirdBindings(
    _openLadybirdLibrary(),
  );

  // Cancels an in-progress download. No-op for downloads that have already
  // finished/failed/been canceled.
  static void cancelDownload(int id) {
    _staticBindings.cancel_download(id);
  }

  // Opens the downloaded file with the host OS's default handler.
  static void openDownload(int id) {
    _staticBindings.open_download(id);
  }

  // Reveals the downloaded file in the host OS's file manager.
  static void showDownloadInFolder(int id) {
    _staticBindings.show_download_in_folder(id);
  }

  // Drops completed/canceled/failed downloads from the engine's tracked
  // list. In-progress downloads are left untouched.
  static void pruneInactiveDownloads() {
    _staticBindings.prune_inactive_downloads();
  }

  void copySelection() {
    _bindings.copy_selection(_viewId);
  }

  // Keeps [_pendingPasteText] in step with the real OS clipboard. Reading it
  // needs an await, so every path that can lead to the engine reading the
  // clipboard refreshes the cache first: the engine's synchronous
  // GetClipboardTextCallback can only hand back what is already cached.
  //
  // Best effort by design -- a context menu action must still run when the
  // platform clipboard can't be read, and one of them ("Paste") is all that
  // depends on this.
  Future<void> _refreshClipboardTextCache() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      LadybirdController._pendingPasteText = data?.text;
    } catch (error) {
      debugPrint('Could not read the system clipboard: $error');
    }
  }

  Future<void> pasteFromClipboard() async {
    await _refreshClipboardTextCache();
    _bindings.paste_from_clipboard(_viewId);
  }

  void selectAll() {
    _bindings.select_all(_viewId);
  }

  // Asks the engine for this view's page source. It answers by opening a new
  // tab (see [onNewWebView]) showing the syntax-highlighted source; nothing is
  // returned, so there is nothing to await here.
  void viewSource() {
    _bindings.view_source(_viewId);
  }

  // Commits text from a platform input method (e.g. a Flutter soft keyboard)
  // into the currently-focused editable element, replacing any marked text.
  void commitTextFromInputMethod(String text) {
    final ffi.Pointer<Utf8> textPointer = text.toNativeUtf8();
    _bindings.commit_text_from_input_method(
      _viewId,
      textPointer.cast<ffi.Char>(),
    );
    malloc.free(textPointer);
  }

  // Sets in-progress (preedit/marked) composition text, used by predictive
  // input methods to preview text before it's committed.
  void setMarkedTextFromInputMethod(String text) {
    final ffi.Pointer<Utf8> textPointer = text.toNativeUtf8();
    _bindings.set_marked_text_from_input_method(
      _viewId,
      textPointer.cast<ffi.Char>(),
    );
    malloc.free(textPointer);
  }

  // Finalizes (commits in place) any current marked text.
  void unmarkTextFromInputMethod() {
    _bindings.unmark_text_from_input_method(_viewId);
  }

  // One texture per view, kept for as long as the view lives. Creating a
  // texture is a platform call, so a texture made per mount left the frames
  // before it resolved with nothing to paint -- which is what showed the window
  // behind the page on every tab switch.
  int? _textureId;

  /// The texture this view renders into, if one has been created.
  int? get textureId => _textureId;

  // The size, in physical pixels, of the canvas the texture was made with, on a
  // platform where a texture is a fixed-size canvas that the page is drawn into
  // (Android); null elsewhere.
  Size? _textureCanvasSize;

  /// The fixed size of the current texture, in physical pixels, or null where a
  /// texture takes the size of the page.
  Size? get textureCanvasSize => _textureCanvasSize;

  /// Whether a texture is a canvas of a fixed size that the view makes the
  /// size of, rather than something that follows the size of the page.
  ///
  /// A texture that follows the page's size is resized while frames of the sizes
  /// before it are still on their way, and the box it is shown in is sized on
  /// another thread's schedule again, so at any moment the three can disagree and
  /// the page is stretched to make up the difference. A canvas that never changes
  /// size cannot disagree with anything: frames are drawn into it unscaled, and
  /// the view clips it to the page.
  static bool get usesFixedCanvasTextures => Platform.isAndroid;

  /// Creates the texture this view renders into, if it has none.
  ///
  /// [canvasSize], in physical pixels, is how large the texture is where a
  /// texture is a fixed canvas (see [usesFixedCanvasTextures]), and it should be
  /// at least as large as the view is ever laid out. It is ignored elsewhere.
  Future<int> acquireTexture({Size? canvasSize}) async {
    final existing = _textureId;
    if (existing != null) return existing;

    final canvas = usesFixedCanvasTextures ? canvasSize : null;
    final created = await _channel.invokeMethod<int>(
      'createTexture',
      canvas == null
          ? _viewId
          : <String, Object>{
              'viewId': _viewId,
              'width': canvas.width.round(),
              'height': canvas.height.round(),
            },
    );
    if (created == null) {
      throw StateError('the platform returned no texture for view $_viewId');
    }
    _textureId = created;
    _textureCanvasSize = canvas;
    return created;
  }

  /// Makes a new texture with a canvas of another size and makes it this view's
  /// texture, instead of resizing the one it has: a texture keeps its size for
  /// as long as it lives. The texture it had is not released, so that the view
  /// can stop showing it first; it is returned for the caller to pass to
  /// [unregisterTexture].
  Future<({int textureId, int? previousTextureId})> replaceTexture(
    Size canvasSize,
  ) async {
    final previous = _textureId;
    _textureId = null;
    try {
      final created = await acquireTexture(canvasSize: canvasSize);
      return (textureId: created, previousTextureId: previous);
    } catch (_) {
      // Nothing was made: the view goes on with the texture it had.
      _textureId ??= previous;
      rethrow;
    }
  }

  Future<void> createTexture() async {
    await acquireTexture();
  }

  Future<void> unregisterTexture(int textureId) async {
    await _channel.invokeMethod('unregisterTexture', textureId);
  }

  /// Paces the page by the display it is shown on, as Ladybird's own frontends
  /// do: the engine then makes one frame per refresh, in step with the display.
  /// Without that, frames reach the screen unevenly however fast they are made,
  /// which shows as judder while scrolling. Call it whenever the view's window
  /// may have moved to another display, or that display's refresh rate changed.
  ///
  /// Only macOS lets the engine follow a display for pacing. Everywhere, this
  /// also tells pages how large the screen is.
  void followDisplay(ui.Display display) {
    _reportScreenSize(display);
    if (!_pacesByDisplay) return;
    final next = (
      id: display.id,
      refreshRate: display.refreshRate > 0 ? display.refreshRate : 60.0,
    );
    _lastDisplay = next;
    if (next == _display) return;
    _display = next;
    _applyDisplayMetadata();
  }

  (int, int)? _screenSize;
  static bool _hasReportedScreenSize = false;

  // What pages read as `window.screen`. Without it they read a screen of no
  // size, and sites serve what they would to a phone.
  void _reportScreenSize(ui.Display display) {
    final size = (display.size.width.round(), display.size.height.round());
    if (size.$1 <= 0 || size.$2 <= 0 || size == _screenSize) return;
    try {
      _bindings.set_screen_size(_viewId, size.$1, size.$2);
    } on ArgumentError catch (error) {
      // A native library from before this existed.
      debugPrint('[LibBird] The engine cannot be told the screen size: $error');
    }
    _screenSize = size;
    _hasReportedScreenSize = true;
  }

  // A new view starts out on the display a view was last shown on, so that one
  // opened in the background is paced before it is first shown.
  void _initializeDisplayPacing() {
    // The engine gives a new view the size reported last, so only the first one
    // has to be told, before it loads anything.
    if (!_hasReportedScreenSize) {
      final first = ui.PlatformDispatcher.instance.displays.firstOrNull;
      if (first != null) _reportScreenSize(first);
    }
    if (_pacesByDisplay) {
      _display = _lastDisplay;
      final shown = ui.PlatformDispatcher.instance.displays.firstOrNull;
      if (_display == null && shown != null) {
        followDisplay(shown);
        return;
      }
    }
    _applyDisplayMetadata();
  }

  void _applyDisplayMetadata({double? maximumFramesPerSecond}) {
    final display = _display;
    final refreshRate = display?.refreshRate ?? assumedRefreshRate;
    setDisplayMetadata(
      displayId: display?.id,
      refreshRate: refreshRate,
      maximumFramesPerSecond: maximumFramesPerSecond ?? refreshRate,
    );
  }

  void setDisplayMetadata({
    required double refreshRate,
    double? maximumFramesPerSecond,
    int? displayId,
  }) {
    _bindings.set_display_metadata(
      _viewId,
      displayId != null,
      displayId ?? 0,
      refreshRate,
      maximumFramesPerSecond ?? refreshRate,
    );
  }

  void setMaximumFramesPerSecond(double? maximumFramesPerSecond) {
    _applyDisplayMetadata(maximumFramesPerSecond: maximumFramesPerSecond);
  }

  Future<Map<String, Object?>?> getTextureDiagnostics(int textureId) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        'getTextureDiagnostics',
        textureId,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  bool resizeWindow(Size size) {
    if (size == _lastSize) return false;
    // print("[LibBird] Controller.resizeWindow: size=$size");
    _lastSize = size;
    _bindings.resize_window(_viewId, size.width.round(), size.height.round());
    return true;
  }

  int getSurfaceWidth() {
    return _bindings.get_iosurface_width(_viewId);
  }

  int getSurfaceHeight() {
    return _bindings.get_iosurface_height(_viewId);
  }

  // FlutterBird's own ABI values for dispatchMouseEvent's `type`, mirrored from
  // LadybirdMouseEventType in cpp/engine.h. They are deliberately not the
  // engine's Web::MouseEvent::Type values: the engine inserted MouseCancel
  // before MouseWheel, which is exactly the kind of shift these names exist to
  // absorb.
  static const int mouseDown = 0;
  static const int mouseUp = 1;
  static const int mouseMove = 2;
  static const int mouseLeave = 3;
  static const int mouseWheel = 4;

  // Wheel-delta precision, mirrored from LadybirdWheelDeltaPrecision in
  // cpp/engine.h. Discrete deltas come from stepwise input (mouse wheel
  // notches); precise ones from input reporting exact pixel distances
  // (touchpad panning).
  static const int wheelDiscrete = 0;
  static const int wheelPrecise = 1;

  // Where a wheel event sits in its scroll gesture, mirrored from
  // LadybirdScrollGesturePhase in cpp/engine.h.
  static const int scrollPhaseNone = 0;
  static const int scrollPhaseOngoing = 1;
  static const int scrollPhaseMomentum = 2;
  static const int scrollPhaseEnded = 3;

  void dispatchMouseEvent({
    required int type,
    required int x,
    required int y,
    required int button,
    required int buttons,
    required int modifiers,
    required double wheelDeltaX,
    required double wheelDeltaY,
    int wheelDeltaPrecision = wheelDiscrete,
    int scrollGesturePhase = scrollPhaseNone,
  }) {
    _bindings.dispatch_mouse_event(
      _viewId,
      type,
      x,
      y,
      button,
      buttons,
      modifiers,
      wheelDeltaX,
      wheelDeltaY,
      wheelDeltaPrecision,
      scrollGesturePhase,
    );
  }

  void dispatchKeyEvent({
    required int type,
    required int keycode,
    required int modifiers,
    required int codePoint,
    required bool repeat,
  }) {
    _bindings.dispatch_key_event(
      _viewId,
      type,
      keycode,
      modifiers,
      codePoint,
      repeat,
    );
  }

  // Runs a context menu action the engine handed this view. The engine's own
  // "Paste" action reads the clipboard synchronously while it runs, so the
  // cache is refreshed before control passes to the engine -- hence the wait,
  // and hence the Future.
  Future<bool> activateContextMenuAction(int actionToken) async {
    await _refreshClipboardTextCache();
    return _bindings.activate_context_menu_action(_viewId, actionToken);
  }

  // The widget that last said this view has focus. A tab that moves to another
  // window is shown by a new widget before the old one is disposed, so the old
  // one's parting word must not take the focus from the new one.
  Object? _focusOwner;

  // Tells the engine whether this view holds system focus. WebContent only has a
  // focused navigable while it does, and the actions that work on a selection
  // (select all, copy) as well as text input act on that navigable.
  void setViewFocused(bool focused, {Object? owner}) {
    if (focused) {
      _focusOwner = owner;
    } else if (owner != null && _focusOwner != owner) {
      return;
    }
    if (focused == _lastFocused) return;
    _lastFocused = focused;
    _bindings.set_view_focused(_viewId, focused);
  }

  void dispose() {
    setViewFocused(false);
    _onCloseRequested = null;
    _bindings.set_new_web_view_callback(_viewId, ffi.nullptr);
    _bindings.set_close_view_callback(_viewId, ffi.nullptr);
    _bindings.set_context_menu_request_callback(_viewId, ffi.nullptr);
    _bindings.set_cursor_change_callback(_viewId, ffi.nullptr);
    _bindings.set_cross_site_navigation_callback(_viewId, ffi.nullptr);
    _bindings.set_loading_state_change_callback(_viewId, ffi.nullptr);
    _bindings.set_input_caret_rect_change_callback(_viewId, ffi.nullptr);
    _bindings.set_fullscreen_change_callback(_viewId, ffi.nullptr);
    _bindings.set_navigation_history_change_callback(_viewId, ffi.nullptr);
    urlNotifier.dispose();
    titleNotifier.dispose();
    faviconNotifier.dispose();
    isLoadingNotifier.dispose();
    canGoBackNotifier.dispose();
    canGoForwardNotifier.dispose();
    sessionHistoryNotifier.dispose();
    mouseCursorNotifier.dispose();
    inputCaretRectNotifier.dispose();
    _resizeCallback.close();
    _urlChangeCallback.close();
    _titleChangeCallback.close();
    _faviconChangeCallback.close();
    _crossSiteNavigationCallback.close();
    _loadingStateChangeCallback.close();
    _cursorChangeCallback.close();
    _contextMenuRequestCallback.close();
    _newWebViewCallback.close();
    _closeViewCallback.close();
    _inputCaretRectChangeCallback.close();
    _fullscreenChangeCallback.close();
    _navigationHistoryChangeCallback.close();

    final textureId = _textureId;
    _textureId = null;
    if (textureId != null) unregisterTexture(textureId).ignore();

    _bindings.destroy_web_view(_viewId);
  }
}

ffi.Pointer<ffi.Char> _onAskUserForDownloadPath(
  ffi.Pointer<ffi.Char> suggestion,
) {
  if (LadybirdController.onAskUserForDownloadPath == null) {
    return ffi.nullptr;
  }
  final s = suggestion.cast<Utf8>().toDartString();
  final result = LadybirdController.onAskUserForDownloadPath!(s);
  if (result != null) {
    return result.toNativeUtf8().cast<ffi.Char>();
  }
  return ffi.nullptr;
}

void _onDisplayDownloadConfirmationDialog(
  ffi.Pointer<ffi.Char> name,
  ffi.Pointer<ffi.Char> path,
) {
  if (LadybirdController.onDisplayDownloadConfirmationDialog == null) return;
  final n = name.cast<Utf8>().toDartString();
  final p = path.cast<Utf8>().toDartString();
  LadybirdController.onDisplayDownloadConfirmationDialog!(n, p);
}

void _onDisplayErrorDialog(ffi.Pointer<ffi.Char> message) {
  if (LadybirdController.onDisplayErrorDialog == null) return;
  final msg = message.cast<Utf8>().toDartString();
  LadybirdController.onDisplayErrorDialog!(msg);
}

ffi.Pointer<ffi.Char> _onGetClipboardText() {
  final text = LadybirdController._pendingPasteText;
  if (text == null) return ffi.nullptr;
  return text.toNativeUtf8().cast<ffi.Char>();
}

void _onSetClipboardText(ffi.Pointer<ffi.Char> text) {
  final value = text.cast<Utf8>().toDartString();
  Clipboard.setData(ClipboardData(text: value));
}

void _onDownloadUpdate(ffi.Pointer<ffi.Char> downloadJsonPointer) {
  if (downloadJsonPointer == ffi.nullptr) return;
  final json = downloadJsonPointer.cast<Utf8>().toDartString();
  malloc.free(downloadJsonPointer);

  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) return;
  final download = LadybirdDownloadMapper.fromMap(decoded);

  final downloads = List<LadybirdDownload>.from(
    LadybirdController.downloadsNotifier.value,
  );
  final index = downloads.indexWhere((d) => d.id == download.id);
  if (index == -1) {
    downloads.insert(0, download);
  } else {
    downloads[index] = download;
  }
  LadybirdController.downloadsNotifier.value = downloads;
}

void _onDownloadRemoved(int id) {
  final downloads = LadybirdController.downloadsNotifier.value
      .where((d) => d.id != id)
      .toList();
  LadybirdController.downloadsNotifier.value = downloads;
}
