import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// How the user answered a permission prompt, in the engine's order
/// (`Web::Permissions::PromptOutcome`).
enum PermissionOutcome {
  allowAlways,
  allowOnce,
  block,

  /// The user turned the prompt away without deciding.
  dismissed,
  ignored,

  /// The prompt went away without the user seeing it through; it counts for
  /// nothing.
  cancelled,
}

/// A page asking for a permission.
class PermissionPrompt {
  const PermissionPrompt({
    required this.id,
    required this.viewId,
    required this.name,
    required this.origin,
    required this.isFile,
    required this.showOsHint,
    required this.isSystemDeniedNotice,
  });

  final int id;
  final int viewId;

  /// `geolocation`, `microphone` or `notifications`.
  final String name;

  /// The site the decision is kept for: that of the top-level page.
  final String origin;
  final bool isFile;
  final bool showOsHint;

  /// Not a question: the system keeps the feature from the browser, and this
  /// only tells the user so.
  final bool isSystemDeniedNotice;
}

/// What the user has decided about one permission for one site.
enum PermissionSetting {
  ask,
  allow,

  /// Allowed until the site has not been in use for a while.
  allowOnce,
  block;

  static PermissionSetting parse(Object? value) => switch (value) {
    'allow' => allow,
    'allow-once' => allowOnce,
    'block' => block,
    _ => ask,
  };
}

class SitePermission {
  const SitePermission({
    required this.name,
    required this.setting,
    required this.requestedByPage,
  });

  final String name;
  final PermissionSetting setting;
  final bool requestedByPage;
}

/// The permissions of the site a view shows.
class SitePermissions {
  const SitePermissions({
    required this.origin,
    required this.isOpaque,
    required this.permissions,
  });

  final String origin;

  /// A page with no origin of its own, such as `about:blank`, has nothing a
  /// decision could be kept for.
  final bool isOpaque;
  final List<SitePermission> permissions;
}

enum PictureInPictureEventKind { open, resize, hide, closed, backToTab }

/// Something the floating window of a video has to do.
class PictureInPictureEvent {
  const PictureInPictureEvent({
    required this.kind,
    required this.ownerViewId,
    required this.viewId,
    required this.width,
    required this.height,
  });

  final PictureInPictureEventKind kind;

  /// The tab the video is in.
  final int ownerViewId;

  /// The view the floating window shows.
  final int viewId;

  /// In logical points.
  final int width;
  final int height;
}

/// Whether a view's page has a video that can float, and whether one of its
/// videos is floating now.
typedef VideoState = ({bool available, bool active});

typedef _AvailabilityNative = ffi.Void Function(ffi.Int, ffi.Bool, ffi.Bool);

typedef _PromptNative =
    ffi.Void Function(ffi.Int, ffi.Uint64, ffi.Pointer<ffi.Char>);
typedef _CancelNative = ffi.Void Function(ffi.Int, ffi.Uint64);
typedef _PictureNative =
    ffi.Void Function(ffi.Int, ffi.Int, ffi.Int, ffi.Int, ffi.Int);

/// The engine's site permissions and Picture-in-Picture.
///
/// Notifies its listeners when the prompts waiting for an answer change.
class LadybirdSiteBridge extends ChangeNotifier {
  LadybirdSiteBridge._();

  static final LadybirdSiteBridge instance = LadybirdSiteBridge._();

  late final ffi.DynamicLibrary _library = Platform.isAndroid
      ? ffi.DynamicLibrary.open('libengine.so')
      : ffi.DynamicLibrary.process();

  late final _setPermissionCallbacks = _library
      .lookupFunction<
        ffi.Void Function(
          ffi.Pointer<ffi.NativeFunction<_PromptNative>>,
          ffi.Pointer<ffi.NativeFunction<_CancelNative>>,
        ),
        void Function(
          ffi.Pointer<ffi.NativeFunction<_PromptNative>>,
          ffi.Pointer<ffi.NativeFunction<_CancelNative>>,
        )
      >('set_permission_callbacks');
  late final _promptShown = _library
      .lookupFunction<ffi.Void Function(ffi.Uint64), void Function(int)>(
        'permission_prompt_shown',
      );
  late final _respond = _library
      .lookupFunction<
        ffi.Void Function(ffi.Uint64, ffi.Int),
        void Function(int, int)
      >('respond_permission_prompt');
  late final _getSite = _library
      .lookupFunction<
        ffi.Pointer<ffi.Char> Function(ffi.Int),
        ffi.Pointer<ffi.Char> Function(int)
      >('get_site_permissions');
  late final _setSite = _library
      .lookupFunction<
        ffi.Void Function(
          ffi.Int,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
        ),
        void Function(
          int,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
        )
      >('set_site_permission');
  late final _resetSite = _library
      .lookupFunction<
        ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>),
        void Function(int, ffi.Pointer<ffi.Char>)
      >('reset_site_permissions');
  late final _setPictureCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_PictureNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_PictureNative>>)
      >('set_picture_in_picture_callback');
  late final _setPictureScreen = _library
      .lookupFunction<
        ffi.Void Function(ffi.Int, ffi.Int),
        void Function(int, int)
      >('set_picture_in_picture_screen_size');
  late final _pictureResized = _library
      .lookupFunction<
        ffi.Void Function(ffi.Int, ffi.Int, ffi.Int),
        void Function(int, int, int)
      >('picture_in_picture_resized');
  late final _closePicture = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'close_picture_in_picture',
      );

  late final _setAvailabilityCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_AvailabilityNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_AvailabilityNative>>)
      >('set_picture_in_picture_availability_callback');
  late final _requestAvailability = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'request_picture_in_picture_availability',
      );
  late final _togglePicture = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'toggle_picture_in_picture',
      );

  static const VideoState _noVideo = (available: false, active: false);
  final Map<int, ValueNotifier<VideoState>> _videos = {};
  ffi.NativeCallable<_AvailabilityNative>? _availabilityCallable;

  final Map<int, PermissionPrompt> _prompts = {};
  final Set<int> _shown = {};

  ffi.NativeCallable<_PromptNative>? _promptCallable;
  ffi.NativeCallable<_CancelNative>? _cancelCallable;
  ffi.NativeCallable<_PictureNative>? _pictureCallable;
  void Function(PictureInPictureEvent event)? _onPictureEvent;

  /// Whether prompts are on. The callbacks are held for as long as the engine
  /// may call them, which is as long as the app runs.
  bool get isStarted => _promptCallable != null && _cancelCallable != null;

  /// The permissions there is any use asking for, or null for all of them.
  Set<String>? _offered;

  /// Whether pages can be given the permission [name] at all.
  bool offers(String name) => _offered?.contains(name) ?? true;

  /// Starts showing permission prompts. Returns whether the engine can: a
  /// native library from before this existed cannot, and its pages are then
  /// refused what they ask for.
  ///
  /// Where the app cannot make good on every permission, [only] names those it
  /// can. Pages are refused the others without the user being asked, and
  /// nothing is remembered about it.
  bool start({Set<String>? only}) {
    if (isStarted) return true;
    _offered = only;

    final prompt = ffi.NativeCallable<_PromptNative>.listener(_onPrompt);
    final cancel = ffi.NativeCallable<_CancelNative>.listener(_onCancel);
    try {
      _setPermissionCallbacks(prompt.nativeFunction, cancel.nativeFunction);
    } on ArgumentError catch (error) {
      prompt.close();
      cancel.close();
      debugPrint('Site permissions are not in this engine: $error');
      return false;
    }
    _promptCallable = prompt;
    _cancelCallable = cancel;
    return true;
  }

  void _onPrompt(int viewId, int promptId, ffi.Pointer<ffi.Char> json) {
    final Map<String, Object?> description;
    try {
      description =
          jsonDecode(json.cast<Utf8>().toDartString()) as Map<String, Object?>;
    } finally {
      malloc.free(json);
    }
    final name = description['name'] as String? ?? '';
    if (!offers(name)) {
      _respond(promptId, PermissionOutcome.cancelled.index);
      return;
    }
    _prompts[promptId] = PermissionPrompt(
      id: promptId,
      viewId: viewId,
      name: name,
      origin: description['origin'] as String? ?? '',
      isFile: description['isFile'] == true,
      showOsHint: description['showOsHint'] == true,
      isSystemDeniedNotice: description['systemDenied'] == true,
    );
    notifyListeners();
  }

  void _onCancel(int viewId, int promptId) {
    _shown.remove(promptId);
    if (_prompts.remove(promptId) != null) notifyListeners();
  }

  /// The oldest prompt waiting on [viewId].
  PermissionPrompt? promptFor(int viewId) =>
      _prompts.values.where((prompt) => prompt.viewId == viewId).firstOrNull;

  /// Tells the engine a prompt is on screen, once for each prompt.
  void markShown(int promptId) {
    if (_prompts.containsKey(promptId) && _shown.add(promptId)) {
      _promptShown(promptId);
    }
  }

  void respond(int promptId, PermissionOutcome outcome) {
    if (_prompts.remove(promptId) == null) return;
    _shown.remove(promptId);
    _respond(promptId, outcome.index);
    notifyListeners();
  }

  SitePermissions? sitePermissions(int viewId) {
    if (!isStarted) return null;
    final pointer = _getSite(viewId);
    if (pointer == ffi.nullptr) return null;
    final Map<String, Object?> site;
    try {
      site =
          jsonDecode(pointer.cast<Utf8>().toDartString())
              as Map<String, Object?>;
    } finally {
      malloc.free(pointer);
    }
    return SitePermissions(
      origin: site['origin'] as String? ?? '',
      isOpaque: site['opaque'] == true,
      permissions: [
        for (final row in (site['rows'] as List? ?? const []).whereType<Map>())
          SitePermission(
            name: row['name'] as String? ?? '',
            setting: PermissionSetting.parse(row['decision']),
            requestedByPage: row['requested'] == true,
          ),
      ],
    );
  }

  void setSitePermission(
    int viewId,
    String origin,
    String name,
    PermissionSetting setting,
  ) {
    final decision = switch (setting) {
      PermissionSetting.allow || PermissionSetting.allowOnce => 'allow',
      PermissionSetting.block => 'block',
      PermissionSetting.ask => 'ask',
    };
    using((arena) {
      _setSite(
        viewId,
        origin.toNativeUtf8(allocator: arena).cast(),
        name.toNativeUtf8(allocator: arena).cast(),
        decision.toNativeUtf8(allocator: arena).cast(),
      );
    });
    notifyListeners();
  }

  void resetSitePermissions(int viewId, String origin) {
    using((arena) {
      _resetSite(viewId, origin.toNativeUtf8(allocator: arena).cast());
    });
    notifyListeners();
  }

  // ------------------------------------------------------------ picture in picture

  /// Starts floating videos: [onEvent] says what to do with their windows.
  /// [screenWidth] and [screenHeight] size the windows. Returns whether the
  /// engine can.
  bool startPictureInPicture(
    void Function(PictureInPictureEvent event) onEvent, {
    required int screenWidth,
    required int screenHeight,
  }) {
    _onPictureEvent = onEvent;
    if (_pictureCallable != null) return true;

    final callable = ffi.NativeCallable<_PictureNative>.listener(_onPicture);
    try {
      _setPictureCallback(callable.nativeFunction);
      _setPictureScreen(screenWidth, screenHeight);
    } on ArgumentError catch (error) {
      callable.close();
      debugPrint('Picture-in-Picture is not in this engine: $error');
      return false;
    }
    _pictureCallable = callable;
    _startVideoStates();
    return true;
  }

  void _startVideoStates() {
    final callable = ffi.NativeCallable<_AvailabilityNative>.listener(
      _onAvailability,
    );
    try {
      _setAvailabilityCallback(callable.nativeFunction);
    } on ArgumentError catch (error) {
      callable.close();
      debugPrint('This engine cannot say which pages have video: $error');
      return;
    }
    _availabilityCallable = callable;
  }

  void _onAvailability(int viewId, bool available, bool active) {
    _videoNotifier(viewId).value = (available: available, active: active);
  }

  ValueNotifier<VideoState> _videoNotifier(int viewId) =>
      _videos.putIfAbsent(viewId, () => ValueNotifier(_noVideo));

  /// What [viewId]'s page offers to float, as last asked with
  /// [refreshVideoState]. It stays "nothing" where floating videos is not
  /// possible.
  ValueListenable<VideoState> videoState(int viewId) => _videoNotifier(viewId);

  /// Asks the page again. The answer arrives on [videoState].
  void refreshVideoState(int viewId) {
    if (_availabilityCallable != null) _requestAvailability(viewId);
  }

  /// Floats the page's best video, or brings back the one that is floating.
  /// The press that calls this is the gesture the page's video needs.
  void togglePictureInPicture(int viewId) {
    if (_availabilityCallable != null) _togglePicture(viewId);
  }

  void _onPicture(
    int ownerViewId,
    int viewId,
    int event,
    int width,
    int height,
  ) {
    if (event < 0 || event >= PictureInPictureEventKind.values.length) return;
    _onPictureEvent?.call(
      PictureInPictureEvent(
        kind: PictureInPictureEventKind.values[event],
        ownerViewId: ownerViewId,
        viewId: viewId,
        width: width,
        height: height,
      ),
    );
  }

  void pictureInPictureResized(int viewId, int width, int height) {
    if (_pictureCallable != null) _pictureResized(viewId, width, height);
  }

  void closePictureInPicture(int viewId) {
    if (_pictureCallable != null) _closePicture(viewId);
  }
}
