// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'window_layout.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserWindowLayout)
final browserWindowLayoutProvider = BrowserWindowLayoutProvider._();

final class BrowserWindowLayoutProvider
    extends $NotifierProvider<BrowserWindowLayout, BrowserWindowLayoutState> {
  BrowserWindowLayoutProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserWindowLayoutProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserWindowLayoutHash();

  @$internal
  @override
  BrowserWindowLayout create() => BrowserWindowLayout();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserWindowLayoutState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserWindowLayoutState>(value),
    );
  }
}

String _$browserWindowLayoutHash() =>
    r'db9b5c3bde578d952a75e4fb87c3e42c62e457de';

abstract class _$BrowserWindowLayout
    extends $Notifier<BrowserWindowLayoutState> {
  BrowserWindowLayoutState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<BrowserWindowLayoutState, BrowserWindowLayoutState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserWindowLayoutState, BrowserWindowLayoutState>,
              BrowserWindowLayoutState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(browserWindowState)
final browserWindowStateProvider = BrowserWindowStateFamily._();

final class BrowserWindowStateProvider
    extends
        $FunctionalProvider<
          BrowserWindowState?,
          BrowserWindowState?,
          BrowserWindowState?
        >
    with $Provider<BrowserWindowState?> {
  BrowserWindowStateProvider._({
    required BrowserWindowStateFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'browserWindowStateProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$browserWindowStateHash();

  @override
  String toString() {
    return r'browserWindowStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<BrowserWindowState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BrowserWindowState? create(Ref ref) {
    final argument = this.argument as int;
    return browserWindowState(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserWindowState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserWindowState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrowserWindowStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$browserWindowStateHash() =>
    r'6dc0aa77fd69de9fe84241b2de36bb1fa0d34592';

final class BrowserWindowStateFamily extends $Family
    with $FunctionalFamilyOverride<BrowserWindowState?, int> {
  BrowserWindowStateFamily._()
    : super(
        retry: null,
        name: r'browserWindowStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  BrowserWindowStateProvider call(int windowId) =>
      BrowserWindowStateProvider._(argument: windowId, from: this);

  @override
  String toString() => r'browserWindowStateProvider';
}

@ProviderFor(browserWindowTabIds)
final browserWindowTabIdsProvider = BrowserWindowTabIdsFamily._();

final class BrowserWindowTabIdsProvider
    extends $FunctionalProvider<List<int>, List<int>, List<int>>
    with $Provider<List<int>> {
  BrowserWindowTabIdsProvider._({
    required BrowserWindowTabIdsFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'browserWindowTabIdsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$browserWindowTabIdsHash();

  @override
  String toString() {
    return r'browserWindowTabIdsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<int>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<int> create(Ref ref) {
    final argument = this.argument as int;
    return browserWindowTabIds(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<int> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<int>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrowserWindowTabIdsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$browserWindowTabIdsHash() =>
    r'b7de1947b98438a28beb9d6f18f4f017a0008154';

final class BrowserWindowTabIdsFamily extends $Family
    with $FunctionalFamilyOverride<List<int>, int> {
  BrowserWindowTabIdsFamily._()
    : super(
        retry: null,
        name: r'browserWindowTabIdsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  BrowserWindowTabIdsProvider call(int windowId) =>
      BrowserWindowTabIdsProvider._(argument: windowId, from: this);

  @override
  String toString() => r'browserWindowTabIdsProvider';
}

@ProviderFor(browserWindowActiveTabId)
final browserWindowActiveTabIdProvider = BrowserWindowActiveTabIdFamily._();

final class BrowserWindowActiveTabIdProvider
    extends $FunctionalProvider<int?, int?, int?>
    with $Provider<int?> {
  BrowserWindowActiveTabIdProvider._({
    required BrowserWindowActiveTabIdFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'browserWindowActiveTabIdProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$browserWindowActiveTabIdHash();

  @override
  String toString() {
    return r'browserWindowActiveTabIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int? create(Ref ref) {
    final argument = this.argument as int;
    return browserWindowActiveTabId(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrowserWindowActiveTabIdProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$browserWindowActiveTabIdHash() =>
    r'048924146a379a0b46ebddea47082781d1764ab7';

final class BrowserWindowActiveTabIdFamily extends $Family
    with $FunctionalFamilyOverride<int?, int> {
  BrowserWindowActiveTabIdFamily._()
    : super(
        retry: null,
        name: r'browserWindowActiveTabIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  BrowserWindowActiveTabIdProvider call(int windowId) =>
      BrowserWindowActiveTabIdProvider._(argument: windowId, from: this);

  @override
  String toString() => r'browserWindowActiveTabIdProvider';
}
