import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';
import 'package:ladybird/src/models/context_menu.dart';
import 'package:ladybird/src/models/download.dart';
import 'package:ladybird/src/models/settings.dart';
import 'dart:ui' as ui;

ffi.DynamicLibrary _openLadybirdLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libengine.so');
  }
  return ffi.DynamicLibrary.process();
}

class LadybirdController {
  static const double assumedRefreshRate = 512.0;

  final MethodChannel _channel = MethodChannel('ladybird');
  late final LadybirdBindings _bindings;
  // int? _textureId;
  Size? _lastSize;
  double? _lastDevicePixelRatio;
  late final int _viewId;
  // When null, the initial navigation falls back to [homeUrl], which is
  // derived from the engine's configured search engine.
  final String? initialUrl;
  bool hasNavigatedInitial = false;
  bool hasStartedNavigation = false;

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
  late final ffi.NativeCallable<ffi.Void Function(ffi.Int, ffi.Bool)>
  _newWebViewCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Int, ffi.Bool, ffi.Int, ffi.Int, ffi.Int, ffi.Int)
  >
  _inputCaretRectChangeCallback;

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

  // Set right before triggering a native paste so the synchronous
  // GetClipboardTextCallback (invoked mid-paste, on the same isolate) has
  // something to hand back. See pasteFromClipboard() below.
  static String? _pendingPasteText;

  void Function()? onResize;
  final Set<VoidCallback> _resizeListeners = <VoidCallback>{};
  void Function()? onCrossSiteNavigation;
  void Function(LadybirdContextMenuRequest request)? onContextMenuRequest;
  void Function(int newViewId, bool activateTab)? onNewWebView;

  final ValueNotifier<String> urlNotifier = ValueNotifier("");
  final ValueNotifier<String> titleNotifier = ValueNotifier("Tab");
  final ValueNotifier<dynamic> faviconNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> canGoBackNotifier = ValueNotifier(false);
  final ValueNotifier<bool> canGoForwardNotifier = ValueNotifier(false);
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
        ffi.NativeCallable<ffi.Void Function(ffi.Int, ffi.Bool)>.listener(
          _onNewWebView,
        );
    _bindings.set_new_web_view_callback(
      _viewId,
      _newWebViewCallback.nativeFunction,
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

    if (existingViewId != null) {
      syncUrlFromEngine();
    }

    _refreshNavigationState();
    assumeFixedRefreshRate();

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

      final request = LadybirdContextMenuRequestMapper.fromMap(
        Map<String, dynamic>.from(decoded),
      );
      onContextMenuRequest?.call(request);
    } finally {
      malloc.free(menuJson);
    }
  }

  void _onNewWebView(int newViewId, bool activateTab) {
    if (newViewId <= 0) return;
    onNewWebView?.call(newViewId, activateTab);
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

  String getBookmarksJson() {
    final ptr = _bindings.get_bookmarks_json();
    if (ptr == ffi.nullptr) return '[]';
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return json;
  }

  void toggleBookmarkForCurrentView() {
    _bindings.toggle_bookmark_for_view(_viewId);
  }

  bool isCurrentViewBookmarked() {
    return _bindings.is_current_view_bookmarked(_viewId);
  }

  String getHistoryAutocompleteJson(String query, {int limit = 8}) {
    final queryPtr = query.toNativeUtf8();
    final ptr = _bindings.history_autocomplete_json(
      queryPtr.cast<ffi.Char>(),
      limit,
    );
    malloc.free(queryPtr);
    if (ptr == ffi.nullptr) return '[]';
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return json;
  }

  // Returns the engine's built-in search engines (name + query URL
  // template), as shipped by WebView::builtin_search_engines().
  List<LadybirdSearchEngine> getBuiltinSearchEngines() {
    final ptr = _bindings.get_builtin_search_engines_json();
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
  String? getSearchEngineName() {
    final ptr = _bindings.get_search_engine_name();
    if (ptr == ffi.nullptr) return null;
    final name = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return name;
  }

  // Sets the active search engine by name. Pass null to clear the selection
  // and fall back to [fallbackSearchEngine].
  void setSearchEngine(String? name) {
    if (name == null || name.isEmpty) {
      _bindings.set_search_engine(ffi.nullptr);
      return;
    }
    final namePtr = name.toNativeUtf8();
    _bindings.set_search_engine(namePtr.cast<ffi.Char>());
    malloc.free(namePtr);
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
    final engines = getBuiltinSearchEngines();
    final wantedName = getSearchEngineName() ?? fallbackSearchEngine.name;

    for (final engine in engines) {
      if (engine.name == wantedName) return engine;
    }
    return engines.isNotEmpty ? engines.first : fallbackSearchEngine;
  }

  // The home/new-tab URL for the active search engine, e.g.
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
  List<LadybirdConfigVariableDefinition> getConfigVariableDefinitions() {
    final ptr = _bindings.get_config_variable_definitions_json();
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

  // Returns the current value of a config variable by name, or null if the
  // name isn't recognized by the engine.
  dynamic getConfigVariable(String name) {
    final namePtr = name.toNativeUtf8();
    final ptr = _bindings.get_config_variable_json(namePtr.cast<ffi.Char>());
    malloc.free(namePtr);
    if (ptr == ffi.nullptr) return null;

    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);
    return jsonDecode(json);
  }

  // Sets a config variable by name. Returns false if the name isn't
  // recognized by the engine (invalid values for a known variable are
  // silently ignored, matching engine behavior).
  bool setConfigVariable(String name, Object? value) {
    final namePtr = name.toNativeUtf8();
    final valuePtr = jsonEncode(value).toNativeUtf8();
    final result = _bindings.set_config_variable_json(
      namePtr.cast<ffi.Char>(),
      valuePtr.cast<ffi.Char>(),
    );
    malloc.free(namePtr);
    malloc.free(valuePtr);
    return result;
  }

  // Returns a full snapshot of every engine setting (search engine, tab
  // settings, zoom, languages, browsing behavior, autoplay, etc), as defined
  // by WebView::Settings::serialize_json().
  Map<String, dynamic> getSettingsJson() {
    final ptr = _bindings.get_settings_json();
    if (ptr == ffi.nullptr) return const {};
    final json = ptr.cast<Utf8>().toDartString();
    malloc.free(ptr);

    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return const {};
    return decoded;
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

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    LadybirdController._pendingPasteText = data?.text;
    _bindings.paste_from_clipboard(_viewId);
  }

  void selectAll() {
    _bindings.select_all(_viewId);
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

  Future<int> createTexture() async {
    return await _channel.invokeMethod('createTexture', _viewId);
  }

  Future<void> unregisterTexture(int textureId) async {
    await _channel.invokeMethod('unregisterTexture', textureId);
  }

  void assumeFixedRefreshRate() {
    setDisplayMetadata(
      refreshRate: assumedRefreshRate,
      maximumFramesPerSecond: assumedRefreshRate,
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
    setDisplayMetadata(
      refreshRate: assumedRefreshRate,
      maximumFramesPerSecond: maximumFramesPerSecond ?? assumedRefreshRate,
    );
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

  void dispatchMouseEvent({
    required int type,
    required int x,
    required int y,
    required int button,
    required int buttons,
    required int modifiers,
    required double wheelDeltaX,
    required double wheelDeltaY,
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

  bool activateContextMenuAction(int actionToken) {
    return _bindings.activate_context_menu_action(_viewId, actionToken);
  }

  void dispose() {
    _bindings.set_new_web_view_callback(_viewId, ffi.nullptr);
    _bindings.set_context_menu_request_callback(_viewId, ffi.nullptr);
    _bindings.set_cursor_change_callback(_viewId, ffi.nullptr);
    _bindings.set_cross_site_navigation_callback(_viewId, ffi.nullptr);
    _bindings.set_loading_state_change_callback(_viewId, ffi.nullptr);
    _bindings.set_input_caret_rect_change_callback(_viewId, ffi.nullptr);
    urlNotifier.dispose();
    titleNotifier.dispose();
    faviconNotifier.dispose();
    isLoadingNotifier.dispose();
    canGoBackNotifier.dispose();
    canGoForwardNotifier.dispose();
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
    _inputCaretRectChangeCallback.close();
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
