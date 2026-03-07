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

@ProviderFor(browserTab)
final browserTabProvider = BrowserTabFamily._();

final class BrowserTabProvider
    extends
        $FunctionalProvider<
          LadybirdController?,
          LadybirdController?,
          LadybirdController?
        >
    with $Provider<LadybirdController?> {
  BrowserTabProvider._({
    required BrowserTabFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'browserTabProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$browserTabHash();

  @override
  String toString() {
    return r'browserTabProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<LadybirdController?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LadybirdController? create(Ref ref) {
    final argument = this.argument as int;
    return browserTab(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LadybirdController? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LadybirdController?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrowserTabProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$browserTabHash() => r'a6a79182332de39028861dd0b3562c15a9deff6a';

final class BrowserTabFamily extends $Family
    with $FunctionalFamilyOverride<LadybirdController?, int> {
  BrowserTabFamily._()
    : super(
        retry: null,
        name: r'browserTabProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  BrowserTabProvider call(int viewId) =>
      BrowserTabProvider._(argument: viewId, from: this);

  @override
  String toString() => r'browserTabProvider';
}
