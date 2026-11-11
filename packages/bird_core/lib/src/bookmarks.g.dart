// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bookmarkStore)
final bookmarkStoreProvider = BookmarkStoreProvider._();

final class BookmarkStoreProvider
    extends $FunctionalProvider<BookmarkStore, BookmarkStore, BookmarkStore>
    with $Provider<BookmarkStore> {
  BookmarkStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarkStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarkStoreHash();

  @$internal
  @override
  $ProviderElement<BookmarkStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BookmarkStore create(Ref ref) {
    return bookmarkStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookmarkStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookmarkStore>(value),
    );
  }
}

String _$bookmarkStoreHash() => r'594ee73682eeafaa91557231057308ff9eaeaa57';
