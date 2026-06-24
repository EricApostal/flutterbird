// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tab_layout_mode.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserTabLayoutModeController)
final browserTabLayoutModeControllerProvider =
    BrowserTabLayoutModeControllerProvider._();

final class BrowserTabLayoutModeControllerProvider
    extends
        $NotifierProvider<
          BrowserTabLayoutModeController,
          BrowserTabLayoutMode
        > {
  BrowserTabLayoutModeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserTabLayoutModeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserTabLayoutModeControllerHash();

  @$internal
  @override
  BrowserTabLayoutModeController create() => BrowserTabLayoutModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserTabLayoutMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserTabLayoutMode>(value),
    );
  }
}

String _$browserTabLayoutModeControllerHash() =>
    r'2e94fb36e0e2fcf9fa1cdbb2be2b947f62a4162d';

abstract class _$BrowserTabLayoutModeController
    extends $Notifier<BrowserTabLayoutMode> {
  BrowserTabLayoutMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BrowserTabLayoutMode, BrowserTabLayoutMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserTabLayoutMode, BrowserTabLayoutMode>,
              BrowserTabLayoutMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
