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

String _$browserOmniboxHash() => r'a18425f4ec74bc35b6ae90c4c3e7bc3c5cbcaa5c';

abstract class _$BrowserOmnibox extends $Notifier<BrowserOmniboxState> {
  BrowserOmniboxState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<BrowserOmniboxState, BrowserOmniboxState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BrowserOmniboxState, BrowserOmniboxState>,
              BrowserOmniboxState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
