// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browser.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserTabController)
final browserTabControllerProvider = BrowserTabControllerProvider._();

final class BrowserTabControllerProvider
    extends $NotifierProvider<BrowserTabController, List<LadybirdController>> {
  BrowserTabControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserTabControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserTabControllerHash();

  @$internal
  @override
  BrowserTabController create() => BrowserTabController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LadybirdController> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LadybirdController>>(value),
    );
  }
}

String _$browserTabControllerHash() =>
    r'e4264e307986cca1fb3a8ee0b29674fd31d1d39a';

abstract class _$BrowserTabController
    extends $Notifier<List<LadybirdController>> {
  List<LadybirdController> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<List<LadybirdController>, List<LadybirdController>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<LadybirdController>, List<LadybirdController>>,
              List<LadybirdController>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
