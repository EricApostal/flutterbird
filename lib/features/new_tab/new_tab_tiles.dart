import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/favicon_or_icon.dart';

/// Whether a click asks for a tab of its own, as one with Command (Control
/// elsewhere than a Mac) held does.
bool get wantsOwnTab => defaultTargetPlatform == TargetPlatform.macOS
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// Something on the new tab page that goes somewhere.
@immutable
class NewTabLink {
  const NewTabLink({
    required this.url,
    required this.label,
    required this.onOpen,
    this.favicon,
    this.detail = '',
    this.menu = const [],
  });

  final String url;
  final String label;
  final String? favicon;

  /// What is said beside it in a list, such as how long ago it was seen.
  final String detail;

  /// Goes there, in a tab of its own where asked.
  final void Function({required bool ownTab}) onOpen;

  /// What else can be done with it.
  final List<BirdMenuEntry> menu;

  void showMenu(BuildContext context, Offset position) =>
      showBirdMenu(context, position, [
        BirdMenuItem('Open', onSelected: () => onOpen(ownTab: false)),
        BirdMenuItem('Open in New Tab', onSelected: () => onOpen(ownTab: true)),
        BirdMenuItem(
          'Copy Address',
          onSelected: () => Clipboard.setData(ClipboardData(text: url)),
        ),
        if (menu.isNotEmpty) ...[const BirdMenuItem.separator(), ...menu],
      ]);
}

// A click, a click for a tab of its own, and the context menu.
class _LinkPressable extends StatelessWidget {
  const _LinkPressable({required this.link, required this.builder});

  final NewTabLink link;
  final Widget Function(BuildContext context, BirdPressState state) builder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTertiaryTapUp: (_) => link.onOpen(ownTab: true),
      child: BirdPressable(
        onPressed: () => link.onOpen(ownTab: wantsOwnTab),
        onSecondaryTapDown: (details) =>
            link.showMenu(context, details.globalPosition),
        semanticLabel: link.label,
        cursor: SystemMouseCursors.click,
        builder: builder,
      ),
    );
  }
}

/// A site's icon, or the first letter of its name on a colour of its own.
class SiteIcon extends StatelessWidget {
  const SiteIcon({
    required this.label,
    required this.favicon,
    required this.size,
    super.key,
  });

  final String label;
  final String? favicon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = favicon;
    if (icon != null && icon.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 6),
        child: FaviconOrIcon(
          favicon: icon,
          fallback: BirdGlyph.globe,
          size: size,
        ),
      );
    }

    final trimmed = label.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    // The same name is the same colour every time the app is run.
    var hash = 0;
    for (final unit in trimmed.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    final colour = HSLColor.fromAHSL(
      1,
      (hash % 360).toDouble(),
      0.42,
      context.bird.isDark ? 0.52 : 0.46,
    ).toColor();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Text(
        letter,
        style: context.birdText(
          color: const Color(0xFFFFFFFF),
          size: size * 0.58,
          weight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

const double kSiteTileWidth = 92;

/// A square for a site: its icon over its name.
class SiteTile extends StatelessWidget {
  const SiteTile({required this.link, super.key});

  final NewTabLink link;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return _LinkPressable(
      link: link,
      builder: (context, state) => BirdFocusRing(
        visible: state.focused,
        radius: 10,
        child: Container(
          width: kSiteTileWidth,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          decoration: BoxDecoration(
            color: state.pressed
                ? colors.pressed
                : state.hovered
                ? colors.hover
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.panelBorder),
                ),
                child: SiteIcon(
                  label: link.label,
                  favicon: link.favicon,
                  size: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                link.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.birdText(size: BirdTextSize.small),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line in a list of pages.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link});

  final NewTabLink link;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return _LinkPressable(
      link: link,
      builder: (context, state) => BirdFocusRing(
        visible: state.focused,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: state.pressed
                ? colors.pressed
                : state.hovered
                ? colors.hover
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(BirdRadius.menu),
          ),
          child: Row(
            children: [
              SiteIcon(label: link.label, favicon: link.favicon, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.birdText(),
                ),
              ),
              if (link.detail.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  link.detail,
                  style: context.birdText(
                    color: colors.textSecondary,
                    size: BirdTextSize.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A named card holding a list of pages.
class LinkListCard extends StatelessWidget {
  const LinkListCard({required this.title, required this.links, super.key});

  final String title;
  final List<NewTabLink> links;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SectionTitle(title),
          ),
          for (final link in links) _LinkRow(link: link),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: context.birdText(
      color: context.bird.textSecondary,
      size: BirdTextSize.small,
      weight: FontWeight.w600,
    ),
  );
}
