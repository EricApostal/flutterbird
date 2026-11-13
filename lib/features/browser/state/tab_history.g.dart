// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tab_history.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TabHistoryController)
final tabHistoryControllerProvider = TabHistoryControllerFamily._();

final class TabHistoryControllerProvider
    extends $NotifierProvider<TabHistoryController, TabHistoryState> {
  TabHistoryControllerProvider._({
    required TabHistoryControllerFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'tabHistoryControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tabHistoryControllerHash();

  @override
  String toString() {
    return r'tabHistoryControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TabHistoryController create() => TabHistoryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TabHistoryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TabHistoryState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TabHistoryControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tabHistoryControllerHash() =>
    r'21a210cfe7985b3061276bc44fc8e8010b407254';

final class TabHistoryControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TabHistoryController,
          TabHistoryState,
          TabHistoryState,
          TabHistoryState,
          int
        > {
  TabHistoryControllerFamily._()
    : super(
        retry: null,
        name: r'tabHistoryControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TabHistoryControllerProvider call(int viewId) =>
      TabHistoryControllerProvider._(argument: viewId, from: this);

  @override
  String toString() => r'tabHistoryControllerProvider';
}

abstract class _$TabHistoryController extends $Notifier<TabHistoryState> {
  late final _$args = ref.$arg as int;
  int get viewId => _$args;

  TabHistoryState build(int viewId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TabHistoryState, TabHistoryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TabHistoryState, TabHistoryState>,
              TabHistoryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
