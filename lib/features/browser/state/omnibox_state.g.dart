// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'omnibox_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BrowserOmnibox)
final browserOmniboxProvider = BrowserOmniboxProvider._();

final class BrowserOmniboxProvider
    extends $NotifierProvider<BrowserOmnibox, BrowserOmniboxState> {
  BrowserOmniboxProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'browserOmniboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$browserOmniboxHash();

  @$internal
  @override
  BrowserOmnibox create() => BrowserOmnibox();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BrowserOmniboxState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BrowserOmniboxState>(value),
    );
  }
}

String _$browserOmniboxHash() => r'8100d185cb3b2327d3c1e37fc25dcf89b624ee78';

abstract class _$BrowserOmnibox extends $Notifier<BrowserOmniboxState> {
  BrowserOmniboxState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BrowserOmniboxState, BrowserOmniboxState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserOmniboxState, BrowserOmniboxState>,
              BrowserOmniboxState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
