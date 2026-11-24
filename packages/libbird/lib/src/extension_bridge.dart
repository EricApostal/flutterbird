import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// One extension's world in one document: the place a content script runs.
class ExtensionContextInfo {
  const ExtensionContextInfo({
    required this.contextId,
    required this.viewId,
    required this.extensionUuid,
    required this.url,
    required this.isTopLevel,
  });

  /// Unique across processes for as long as the context exists.
  final int contextId;

  /// The tab the document is in, or null when it is not one the app knows.
  final int? viewId;

  /// The uuid of the extension's `moz-extension://<uuid>` origin.
  final String extensionUuid;
  final String url;
  final bool isTopLevel;
}

/// A string an extension context sent to the browser.
class ExtensionEngineMessage {
  const ExtensionEngineMessage(this.contextId, this.payload);

  final int contextId;
  final String payload;
}

typedef _CreatedNative =
    ffi.Void Function(
      ffi.Uint64,
      ffi.Int,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Bool,
    );
typedef _DestroyedNative = ffi.Void Function(ffi.Uint64);
typedef _MessageNative = ffi.Void Function(ffi.Uint64, ffi.Pointer<ffi.Char>);

/// A request an extension may want to block, held until it is answered.
class ExtensionInterceptRequest {
  const ExtensionInterceptRequest({
    required this.requestId,
    required this.viewId,
    required this.detailsJson,
  });

  final int requestId;

  /// The tab the request is for, or null when it is not one the app knows.
  final int? viewId;

  /// The request as a webRequest listener sees it, as JSON.
  final String detailsJson;
}

typedef _InterceptNative =
    ffi.Void Function(ffi.Uint64, ffi.Int, ffi.Pointer<ffi.Char>);

typedef _SetCallbacksNative =
    ffi.Void Function(
      ffi.Pointer<ffi.NativeFunction<_CreatedNative>>,
      ffi.Pointer<ffi.NativeFunction<_DestroyedNative>>,
      ffi.Pointer<ffi.NativeFunction<_MessageNative>>,
    );
typedef _SetCallbacks =
    void Function(
      ffi.Pointer<ffi.NativeFunction<_CreatedNative>>,
      ffi.Pointer<ffi.NativeFunction<_DestroyedNative>>,
      ffi.Pointer<ffi.NativeFunction<_MessageNative>>,
    );

/// The engine's end of the extension channel.
///
/// The engine only carries strings between the browser and the extension
/// worlds that run inside web content processes; what they mean is decided by
/// whoever listens here. It is process-wide, like the downloads, because
/// extensions are not tied to one tab.
class ExtensionEngineBridge {
  ExtensionEngineBridge._();

  static final ExtensionEngineBridge instance = ExtensionEngineBridge._();

  final StreamController<ExtensionContextInfo> _created =
      StreamController<ExtensionContextInfo>.broadcast();
  final StreamController<int> _destroyed = StreamController<int>.broadcast();
  final StreamController<ExtensionEngineMessage> _messages =
      StreamController<ExtensionEngineMessage>.broadcast();

  ffi.NativeCallable<_CreatedNative>? _createdCallable;
  ffi.NativeCallable<_DestroyedNative>? _destroyedCallable;
  ffi.NativeCallable<_MessageNative>? _messageCallable;
  ffi.NativeCallable<_InterceptNative>? _interceptCallable;
  final StreamController<ExtensionInterceptRequest> _intercepts =
      StreamController<ExtensionInterceptRequest>.broadcast();

  late final ffi.DynamicLibrary _library = Platform.isAndroid
      ? ffi.DynamicLibrary.open('libengine.so')
      : ffi.DynamicLibrary.process();

  late final _SetCallbacks _setCallbacks = _library
      .lookupFunction<_SetCallbacksNative, _SetCallbacks>(
        'set_extension_callbacks',
      );
  late final void Function(ffi.Pointer<ffi.NativeFunction<_InterceptNative>>)
  _setInterceptCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_InterceptNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_InterceptNative>>)
      >('set_extension_intercept_callback');
  late final bool Function(int, ffi.Pointer<ffi.Char>) _respondToIntercept =
      _library.lookupFunction<
        ffi.Bool Function(ffi.Uint64, ffi.Pointer<ffi.Char>),
        bool Function(int, ffi.Pointer<ffi.Char>)
      >('respond_extension_intercept');
  late final void Function(ffi.Pointer<ffi.Char>) _setState = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Char>),
        void Function(ffi.Pointer<ffi.Char>)
      >('set_extension_state');
  late final bool Function(int, ffi.Pointer<ffi.Char>) _send = _library
      .lookupFunction<
        ffi.Bool Function(ffi.Uint64, ffi.Pointer<ffi.Char>),
        bool Function(int, ffi.Pointer<ffi.Char>)
      >('send_extension_message');

  /// A context appeared: a document matched one of an extension's content
  /// scripts and its world is ready.
  Stream<ExtensionContextInfo> get contextCreated => _created.stream;

  /// A context is gone: its document was destroyed or its process died.
  Stream<int> get contextDestroyed => _destroyed.stream;

  /// A context sent a string to the browser.
  Stream<ExtensionEngineMessage> get messages => _messages.stream;

  /// Requests held until [respondToIntercept] is called for them. Only
  /// requests are held while someone listens here; with no listener the engine
  /// is not asked to hold any.
  Stream<ExtensionInterceptRequest> get interceptRequests => _intercepts.stream;

  bool get isStarted => _createdCallable != null;

  /// Registers with the engine. Call once the engine is initialized; calling
  /// again does nothing.
  void start() {
    if (isStarted) return;

    final created = ffi.NativeCallable<_CreatedNative>.listener(_onCreated);
    final destroyed = ffi.NativeCallable<_DestroyedNative>.listener(
      _onDestroyed,
    );
    final message = ffi.NativeCallable<_MessageNative>.listener(_onMessage);

    _createdCallable = created;
    _destroyedCallable = destroyed;
    _messageCallable = message;

    _setCallbacks(
      created.nativeFunction,
      destroyed.nativeFunction,
      message.nativeFunction,
    );
  }

  /// Starts receiving requests to intercept. Call after [start], and only when
  /// something will answer them: each is held until it is answered.
  void startIntercepting() {
    if (_interceptCallable != null) return;
    final callable = ffi.NativeCallable<_InterceptNative>.listener(
      _onIntercept,
    );
    _interceptCallable = callable;
    _setInterceptCallback(callable.nativeFunction);
  }

  /// Answers a held request with [verdictJson]: `{}` to let it go ahead, or
  /// an object with any of `cancel`, `redirectUrl` and `requestHeaders`.
  bool respondToIntercept(int requestId, String verdictJson) {
    final pointer = verdictJson.toNativeUtf8();
    try {
      return _respondToIntercept(requestId, pointer.cast<ffi.Char>());
    } finally {
      malloc.free(pointer);
    }
  }

  /// Unregisters from the engine and releases the callbacks. [start] may be
  /// called again afterwards.
  void stop() {
    if (!isStarted) return;

    _setCallbacks(ffi.nullptr, ffi.nullptr, ffi.nullptr);
    if (_interceptCallable != null) {
      _setInterceptCallback(ffi.nullptr);
      _interceptCallable?.close();
      _interceptCallable = null;
    }
    _createdCallable?.close();
    _destroyedCallable?.close();
    _messageCallable?.close();
    _createdCallable = null;
    _destroyedCallable = null;
    _messageCallable = null;
  }

  /// Gives every web content process, now and as they start, the JSON that
  /// says which content scripts to run where, and the shim they run with.
  void setState(String json) {
    final pointer = json.toNativeUtf8();
    try {
      _setState(pointer.cast<ffi.Char>());
    } finally {
      malloc.free(pointer);
    }
  }

  /// Sends [payload] to a context. False when its process has gone.
  bool send(int contextId, String payload) {
    final pointer = payload.toNativeUtf8();
    try {
      return _send(contextId, pointer.cast<ffi.Char>());
    } finally {
      malloc.free(pointer);
    }
  }

  // The engine hands over strings it allocated and expects them freed here,
  // like every other string callback in the engine.
  String _takeString(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return '';
    try {
      return pointer.cast<Utf8>().toDartString();
    } finally {
      malloc.free(pointer);
    }
  }

  void _onCreated(
    int contextId,
    int viewId,
    ffi.Pointer<ffi.Char> extensionUuid,
    ffi.Pointer<ffi.Char> url,
    bool isTopLevel,
  ) {
    _created.add(
      ExtensionContextInfo(
        contextId: contextId,
        viewId: viewId < 0 ? null : viewId,
        extensionUuid: _takeString(extensionUuid),
        url: _takeString(url),
        isTopLevel: isTopLevel,
      ),
    );
  }

  void _onDestroyed(int contextId) => _destroyed.add(contextId);

  void _onIntercept(
    int requestId,
    int viewId,
    ffi.Pointer<ffi.Char> detailsJson,
  ) {
    _intercepts.add(
      ExtensionInterceptRequest(
        requestId: requestId,
        viewId: viewId < 0 ? null : viewId,
        detailsJson: _takeString(detailsJson),
      ),
    );
  }

  void _onMessage(int contextId, ffi.Pointer<ffi.Char> payload) {
    _messages.add(ExtensionEngineMessage(contextId, _takeString(payload)));
  }
}
