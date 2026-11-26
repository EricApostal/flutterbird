/// What a context menu was asked for on, as far as the engine says. A native
/// library from before it said any of this leaves everything null.
class LadybirdContextMenuTarget {
  const LadybirdContextMenuTarget({
    this.linkUrl,
    this.mediaUrl,
    this.imageData,
  });

  factory LadybirdContextMenuTarget.fromMap(Map<String, dynamic> map) {
    String? text(String key) {
      final value = map[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return LadybirdContextMenuTarget(
      linkUrl: text('linkURL'),
      mediaUrl: text('mediaURL'),
      imageData: text('imageData'),
    );
  }

  /// The address of the link pressed on.
  final String? linkUrl;

  /// The address of the picture, video or sound pressed on.
  final String? mediaUrl;

  /// The picture pressed on, as a base64 PNG.
  final String? imageData;
}
