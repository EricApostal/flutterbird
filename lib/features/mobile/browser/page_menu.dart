import 'dart:math' as math;

import 'package:bird_session/bird_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/downloads_page.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';

List<EngineMenuEntry> _entries(List<LadybirdContextMenuEntry> entries) => [
  for (final entry in entries)
    EngineMenuEntry(
      kind: entry.kind,
      label: entry.text,
      token: entry.actionToken,
      enabled: entry.enabled,
      checkable: entry.checkable,
      checked: entry.checked,
      items: _entries(entry.items),
    ),
];

IconData _iconFor(PageMenuRole role) => switch (role) {
  PageMenuRole.openInNewTab ||
  PageMenuRole.openImageInNewTab ||
  PageMenuRole.openMediaInNewTab => Icons.add_box_outlined,
  PageMenuRole.openImage => Icons.image_outlined,
  PageMenuRole.openMedia => Icons.play_circle_outline,
  PageMenuRole.copyLink ||
  PageMenuRole.copyLinkToHighlight => Icons.link_rounded,
  PageMenuRole.copyEmail => Icons.alternate_email,
  PageMenuRole.copyPhone => Icons.phone_outlined,
  PageMenuRole.copyImage ||
  PageMenuRole.copyImageAddress ||
  PageMenuRole.copyMediaAddress ||
  PageMenuRole.copy => Icons.copy_rounded,
  PageMenuRole.downloadLink ||
  PageMenuRole.downloadImage => Icons.file_download_outlined,
  PageMenuRole.playPause => Icons.play_arrow_rounded,
  PageMenuRole.mute => Icons.volume_up_outlined,
  PageMenuRole.controls => Icons.tune_rounded,
  PageMenuRole.loop => Icons.loop_rounded,
  PageMenuRole.fullscreen => Icons.fullscreen_rounded,
  PageMenuRole.cut => Icons.content_cut_rounded,
  PageMenuRole.paste || PageMenuRole.pastePlain => Icons.content_paste_rounded,
  PageMenuRole.selectAll => Icons.select_all_rounded,
  PageMenuRole.search => Icons.search,
  PageMenuRole.spelling => Icons.spellcheck_rounded,
  PageMenuRole.other => Icons.arrow_forward_rounded,
};

/// What was chosen from the card: something the engine does, or something the
/// app does itself.
sealed class _Choice {
  const _Choice();
}

class _EngineChoice extends _Choice {
  const _EngineChoice(this.item);
  final PageMenuItem item;
}

class _ShareChoice extends _Choice {
  const _ShareChoice(this.url);
  final String url;
}

/// Answers a long press on a page with what a phone browser offers for it: a
/// card for a link, a picture or a video, and a small toolbar for text.
class MobilePageMenu {
  const MobilePageMenu._();

  static Future<void> show({
    required BuildContext context,
    required LadybirdController tab,
    required LadybirdContextMenuRequest request,

    /// Where the finger is, on the screen.
    required Offset position,
  }) async {
    PageSelectionToolbar.dismiss();
    final plan = planPageMenu(request.type, _entries(request.items));

    switch (plan.style) {
      case PageMenuStyle.none:
        return;
      case PageMenuStyle.toolbar:
        HapticFeedback.selectionClick();
        PageSelectionToolbar.show(
          context: context,
          tab: tab,
          anchor: position,
          items: plan.items,
        );
        return;
      case PageMenuStyle.card:
        HapticFeedback.mediumImpact();
    }

    final choice = await _showCard(
      context,
      plan,
      tab.contextMenuTarget,
      position,
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _ShareChoice(:final url):
        await shareText(context, url);
      case _EngineChoice(:final item):
        await _perform(context, tab, item);
    }
  }

  static Future<void> _perform(
    BuildContext context,
    LadybirdController tab,
    PageMenuItem item,
  ) async {
    final shell = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(browserShellProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final before = shell.session.allTabIds.toSet();

    if (!await tab.activateContextMenuAction(item.token)) return;

    switch (item.role) {
      case PageMenuRole.openInNewTab ||
          PageMenuRole.openImageInNewTab ||
          PageMenuRole.openMediaInNewTab:
        // The engine makes the tab and tells the app in its own time.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final opened = shell.session.allTabIds
            .where((id) => !before.contains(id))
            .toList();
        if (opened.isEmpty ||
            shell.session.windows.any((w) => w.activeTabId == opened.last)) {
          return;
        }
        showMobileSnack(
          messenger,
          'Opened in new tab',
          action: 'Switch',
          onAction: () => shell.showTab(opened.last),
        );
      case PageMenuRole.downloadLink || PageMenuRole.downloadImage:
        showMobileSnack(
          messenger,
          'Download started',
          action: 'Details',
          onAction: () {
            if (navigator.mounted) {
              navigator.push(mobilePageRoute<void>(const DownloadsPage()));
            }
          },
        );
      default:
        break;
    }
  }

  static Future<_Choice?> _showCard(
    BuildContext context,
    PageMenuPlan plan,
    LadybirdContextMenuTarget target,
    Offset position,
  ) {
    final screen = MediaQuery.sizeOf(context);
    // It grows from the side of the screen that was pressed.
    final origin = Alignment(
      (position.dx / screen.width * 2 - 1).clamp(-1.0, 1.0) * 0.6,
      (position.dy / screen.height * 2 - 1).clamp(-1.0, 1.0) * 0.6,
    );

    return showGeneralDialog<_Choice>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _PageMenuCard(plan: plan, target: target),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: origin,
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _PageMenuCard extends StatefulWidget {
  const _PageMenuCard({required this.plan, required this.target});

  final PageMenuPlan plan;
  final LadybirdContextMenuTarget target;

  @override
  State<_PageMenuCard> createState() => _PageMenuCardState();
}

class _PageMenuCardState extends State<_PageMenuCard> {
  bool _wholeAddress = false;

  PageMenuPlan get _plan => widget.plan;

  /// The address the card is headed with.
  String? get _address => switch (_plan.subject) {
    PageMenuSubject.link => widget.target.linkUrl,
    _ => widget.target.mediaUrl ?? widget.target.linkUrl,
  };

  String get _title {
    final host = siteHost(_address ?? '');
    return switch (_plan.subject) {
      PageMenuSubject.link => host.isEmpty ? 'Link' : host,
      PageMenuSubject.image => 'Image',
      PageMenuSubject.video => 'Video',
      PageMenuSubject.audio => 'Audio',
      PageMenuSubject.text => 'Text',
    };
  }

  Widget _picture(MobileColors colors) {
    final bytes = decodePicture(widget.target.imageData);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        cacheWidth: 200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Icon(Icons.image_outlined, size: 28),
      );
    }
    return Center(
      child: switch (_plan.subject) {
        PageMenuSubject.link => SiteIcon(url: _address ?? '', size: 28),
        PageMenuSubject.image => const Icon(Icons.image_outlined, size: 28),
        PageMenuSubject.video => const Icon(Icons.movie_outlined, size: 28),
        PageMenuSubject.audio => const Icon(
          Icons.audiotrack_outlined,
          size: 28,
        ),
        PageMenuSubject.text => const Icon(Icons.notes_rounded, size: 28),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final media = MediaQuery.of(context);
    final address = _address;
    final linkUrl = widget.target.linkUrl;
    final mediaUrl = widget.target.mediaUrl;
    // A data: address is the picture itself, which is no use as words.
    bool shareable(String? url) => url != null && !url.startsWith('data:');

    final rows = <Widget>[];
    var group = _plan.items.isEmpty ? 0 : _plan.items.first.group;
    for (final item in _plan.items) {
      if (item.group != group) {
        group = item.group;
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(),
          ),
        );
      }
      rows.add(
        MobileMenuRow(
          icon: _iconFor(item.role),
          label: item.label,
          checked: item.checked ?? false,
          onTap: () => Navigator.of(context).pop(_EngineChoice(item)),
        ),
      );
    }

    final shares = [
      if (shareable(linkUrl)) ('Share link', linkUrl!),
      if (shareable(mediaUrl))
        (
          switch (_plan.subject) {
            PageMenuSubject.video => 'Share video address',
            PageMenuSubject.audio => 'Share audio address',
            _ => 'Share image address',
          },
          mediaUrl!,
        ),
    ];
    for (final (label, url) in shares) {
      rows.add(
        MobileMenuRow(
          icon: Icons.share_outlined,
          label: label,
          onTap: () => Navigator.of(context).pop(_ShareChoice(url)),
        ),
      );
    }

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(360, media.size.width - 40),
            maxHeight: media.size.height * 0.82,
          ),
          child: Material(
            color: colors.menu,
            elevation: 10,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _wholeAddress = !_wholeAddress),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 56,
                            height: 56,
                            color: colors.containerHigh,
                            child: _picture(colors),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: colors.text,
                                ),
                              ),
                              if (address != null && shareable(address))
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    address,
                                    maxLines: _wholeAddress ? 8 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The toolbar by selected text and in text fields.
///
/// It is an overlay entry and not a route: a route would take the focus from
/// the page, which is what the engine's actions on a selection act on, and
/// would put the keyboard away while a field is being edited.
class PageSelectionToolbar {
  const PageSelectionToolbar._();

  /// Whether one is up, for the back button to take it down.
  static final ValueNotifier<bool> visible = ValueNotifier(false);

  static OverlayEntry? _entry;
  static LadybirdController? _tab;

  static void show({
    required BuildContext context,
    required LadybirdController tab,
    required Offset anchor,
    required List<PageMenuItem> items,
  }) {
    dismiss();
    final entry = OverlayEntry(
      builder: (context) => _SelectionToolbarView(
        anchor: anchor,
        items: items,
        onSelected: (item) {
          dismiss();
          tab.activateContextMenuAction(item.token);
        },
      ),
    );
    _entry = entry;
    _tab = tab;
    // What was selected goes with its page.
    tab.isLoadingNotifier.addListener(dismiss);
    tab.urlNotifier.addListener(dismiss);
    Overlay.of(context, rootOverlay: true).insert(entry);
    visible.value = true;
  }

  static void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _tab?.isLoadingNotifier.removeListener(dismiss);
    _tab?.urlNotifier.removeListener(dismiss);
    _tab = null;
    entry
      ..remove()
      ..dispose();
    visible.value = false;
  }
}

class _SelectionToolbarView extends StatefulWidget {
  const _SelectionToolbarView({
    required this.anchor,
    required this.items,
    required this.onSelected,
  });

  final Offset anchor;
  final List<PageMenuItem> items;
  final ValueChanged<PageMenuItem> onSelected;

  @override
  State<_SelectionToolbarView> createState() => _SelectionToolbarViewState();
}

class _SelectionToolbarViewState extends State<_SelectionToolbarView> {
  bool _showingMore = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final media = MediaQuery.of(context);
    final width = media.size.width - 24;
    // About as many as fit side by side, with room for the rest's button.
    final inline = math.max(1, math.min(4, (width - 48) ~/ 78));
    final first = widget.items.take(inline).toList();
    final rest = widget.items.skip(inline).toList();

    Widget content;
    if (_showingMore) {
      content = SizedBox(
        width: 220,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _showingMore = false),
                ),
              ),
              for (final item in rest)
                MobileMenuRow(
                  label: item.label,
                  onTap: () => widget.onSelected(item),
                ),
            ],
          ),
        ),
      );
    } else {
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 6),
            for (final item in first)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.text,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () => widget.onSelected(item),
                child: Text(item.label),
              ),
            if (rest.isNotEmpty)
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () => setState(() => _showingMore = true),
              ),
            const SizedBox(width: 6),
          ],
        ),
      );
    }

    return CustomSingleChildLayout(
      delegate: _AboveFinger(
        anchor: widget.anchor,
        padding: media.viewPadding.copyWith(
          bottom: math.max(media.viewPadding.bottom, media.viewInsets.bottom),
        ),
      ),
      child: TapRegion(
        // A touch elsewhere takes it away and still reaches what was touched.
        onTapOutside: (_) => PageSelectionToolbar.dismiss(),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
          child: Material(
            color: colors.menu,
            elevation: 8,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _AboveFinger extends SingleChildLayoutDelegate {
  _AboveFinger({required this.anchor, required this.padding});

  final Offset anchor;
  final EdgeInsets padding;

  // Clear of the finger and of the line of text under it.
  static const double _above = 44;
  static const double _below = 40;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - 24),
        maxHeight: math.max(0, constraints.maxHeight * 0.5),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = padding.top + 8;
    final bottom = size.height - padding.bottom - childSize.height - 8;
    var y = anchor.dy - _above - childSize.height;
    if (y < top) y = anchor.dy + _below;
    final x = anchor.dx - childSize.width / 2;
    return Offset(
      x.clamp(12.0, math.max(12.0, size.width - childSize.width - 12)),
      y.clamp(top, math.max(top, bottom)),
    );
  }

  @override
  bool shouldRelayout(_AboveFinger old) =>
      old.anchor != anchor || old.padding != padding;
}
