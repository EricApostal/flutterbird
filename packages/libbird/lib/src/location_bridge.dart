import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef _WantedNative = ffi.Void Function(ffi.Bool);

/// Gets the engine its locations on Android, where it cannot get them itself:
/// the engine says when pages are waiting for one, and they are had from the
/// system, after asking the user to let the app have them. Elsewhere there is
/// nothing to do.
///
/// Whether a site may have the location at all is up to the site permission
/// prompts.
class LadybirdLocationBridge {
  LadybirdLocationBridge._();

  static final LadybirdLocationBridge instance = LadybirdLocationBridge._();

  /// How old a position may be and still answer a page that has only now asked.
  static const _freshFor = Duration(seconds: 10);

  late final ffi.DynamicLibrary _library = ffi.DynamicLibrary.open(
    'libengine.so',
  );
  late final _setCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_WantedNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_WantedNative>>)
      >('set_geolocation_callback');
  late final _deliverPosition = _library
      .lookupFunction<
        ffi.Void Function(
          ffi.Double,
          ffi.Double,
          ffi.Double,
          ffi.Double,
          ffi.Double,
          ffi.Double,
          ffi.Double,
        ),
        void Function(double, double, double, double, double, double, double)
      >('deliver_geolocation_position');
  late final _deliverError = _library
      .lookupFunction<
        ffi.Void Function(ffi.Bool, ffi.Pointer<ffi.Char>),
        void Function(bool, ffi.Pointer<ffi.Char>)
      >('deliver_geolocation_error');

  ffi.NativeCallable<_WantedNative>? _wantedCallable;
  final StreamController<void> _refusals = StreamController.broadcast();

  bool _wanted = false;
  bool _starting = false;
  StreamSubscription<Position>? _positions;
  Position? _latest;

  /// Tells of each time a page the user allowed was to have the location and
  /// Android did not let the app have it.
  Stream<void> get refusals => _refusals.stream;

  /// Starts giving the engine locations. Returns whether it can: only on
  /// Android, with a native library new enough to take them.
  bool start() {
    if (!Platform.isAndroid) return false;
    if (_wantedCallable != null) return true;

    final wanted = ffi.NativeCallable<_WantedNative>.listener(_onWanted);
    try {
      _setCallback(wanted.nativeFunction);
    } on ArgumentError catch (error) {
      wanted.close();
      debugPrint('Locations are not in this engine: $error');
      return false;
    }
    _wantedCallable = wanted;
    return true;
  }

  /// The app's page in Android's settings, where a refusal can be taken back.
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  // Called with true each time a page starts waiting, whether or not others
  // already are.
  void _onWanted(bool wanted) {
    _wanted = wanted;
    if (!wanted) {
      _stopListening();
    } else if (_positions == null) {
      unawaited(_listen());
    } else if (_latest case final latest?
        when DateTime.now().difference(latest.timestamp) < _freshFor) {
      // A device lying still may not report again for a while.
      _deliver(latest);
    }
  }

  Future<void> _listen() async {
    if (_starting) return;
    _starting = true;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && _wanted) {
        permission = await Geolocator.requestPermission();
      }
      if (!_wanted) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _fail(
          denied: true,
          message: 'Android does not let the app have the location',
        );
        _refusals.add(null);
        return;
      }
      _positions = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          intervalDuration: const Duration(seconds: 1),
        ),
      ).listen(_deliver, onError: _onLost);
    } on Exception catch (error) {
      if (_wanted) _fail(denied: false, message: '$error');
    } finally {
      _starting = false;
    }
  }

  void _stopListening() {
    unawaited(_positions?.cancel());
    _positions = null;
  }

  // The next page to ask starts afresh.
  void _onLost(Object error) {
    _stopListening();
    _fail(denied: false, message: '$error');
  }

  void _deliver(Position position) {
    if (!_wanted) return;
    _latest = position;
    double known(bool measured, double value) => measured ? value : double.nan;
    _deliverPosition(
      position.latitude,
      position.longitude,
      position.accuracy,
      known(position.hasAltitude, position.altitude),
      known(position.hasAltitudeAccuracy, position.altitudeAccuracy),
      known(position.hasHeading, position.heading),
      known(position.hasSpeed, position.speed),
    );
  }

  void _fail({required bool denied, required String message}) {
    using((arena) {
      _deliverError(denied, message.toNativeUtf8(allocator: arena).cast());
    });
  }
}
