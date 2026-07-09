// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fullscreen_mode.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserFullscreenModeController)
final browserFullscreenModeControllerProvider =
    BrowserFullscreenModeControllerProvider._();

final class BrowserFullscreenModeControllerProvider
    extends $NotifierProvider<BrowserFullscreenModeController, bool> {
  BrowserFullscreenModeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserFullscreenModeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserFullscreenModeControllerHash();

  @$internal
  @override
  BrowserFullscreenModeController create() => BrowserFullscreenModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$browserFullscreenModeControllerHash() =>
    r'3c4cd9928c9cecdebc8a7dba1d0c4508efc93f2f';

abstract class _$BrowserFullscreenModeController extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
