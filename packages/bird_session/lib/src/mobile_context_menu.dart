/// What a long press on a page offers on a phone, worked out from the menu the
/// engine made for a desktop.
library;

/// One entry of the engine's menu.
class EngineMenuEntry {
  const EngineMenuEntry({
    required this.label,
    this.kind = 'action',
    this.token,
    this.enabled = true,
    this.checkable = false,
    this.checked = false,
    this.items = const [],
  });

  /// `action`, `separator` or `submenu`.
  final String kind;
  final String label;
  final int? token;
  final bool enabled;
  final bool checkable;
  final bool checked;
  final List<EngineMenuEntry> items;
}

/// How the menu is shown.
enum PageMenuStyle {
  /// Nothing worth showing: a long press on an empty part of a page does
  /// nothing on a phone.
  none,

  /// A card in the middle of the screen, for a link, a picture or a video.
  card,

  /// A small toolbar by the finger, for selected text and text fields.
  toolbar,
}

/// What the card is about.
enum PageMenuSubject { link, image, video, audio, text }

/// What an entry does, so that it can be given an icon and a place.
enum PageMenuRole {
  openInNewTab,
  openImageInNewTab,
  openImage,
  openMediaInNewTab,
  openMedia,
  copyLink,
  copyEmail,
  copyPhone,
  copyLinkToHighlight,
  copyImage,
  copyImageAddress,
  copyMediaAddress,
  downloadLink,
  downloadImage,
  playPause,
  mute,
  controls,
  loop,
  fullscreen,
  cut,
  copy,
  paste,
  pastePlain,
  selectAll,
  search,
  spelling,
  other,
}

class PageMenuItem {
  const PageMenuItem({
    required this.role,
    required this.label,
    required this.token,
    this.enabled = true,
    this.checked,
    this.group = 0,
  });

  final PageMenuRole role;
  final String label;

  /// What the engine is given to do it.
  final int token;
  final bool enabled;

  /// Null for what cannot be ticked.
  final bool? checked;

  /// Entries of one group are listed together, with a line between groups.
  final int group;
}

class PageMenuPlan {
  const PageMenuPlan(this.style, this.subject, this.items);

  static const PageMenuPlan nothing = PageMenuPlan(
    PageMenuStyle.none,
    PageMenuSubject.text,
    [],
  );

  final PageMenuStyle style;
  final PageMenuSubject subject;
  final List<PageMenuItem> items;
}

// What a phone browser has no use for: windows, files chosen by path, and the
// desktop's own tools.
const Set<String> _leftOut = {
  'Open Link in New Window',
  'Open Link in Private Window',
  'Save Link As…',
  'Inspect',
  'View Page Source',
  'Report Website Issue…',
  'Take Screenshot...',
  'Look Up',
  'Back',
  'Forward',
  'Reload',
  'Picture in Picture',
  'Exit Picture in Picture',
  'No Guesses Found',
};

const Map<String, (PageMenuRole, String)> _known = {
  'Open Link in New Tab': (PageMenuRole.openInNewTab, 'Open in new tab'),
  'Copy Link': (PageMenuRole.copyLink, 'Copy link address'),
  'Copy Email Address': (PageMenuRole.copyEmail, 'Copy email address'),
  'Copy Phone Number': (PageMenuRole.copyPhone, 'Copy phone number'),
  'Copy Link to Highlight': (
    PageMenuRole.copyLinkToHighlight,
    'Copy link to highlight',
  ),
  'Download Linked File': (PageMenuRole.downloadLink, 'Download link'),
  'Open Image in New Tab': (
    PageMenuRole.openImageInNewTab,
    'Open image in new tab',
  ),
  'Open Image': (PageMenuRole.openImage, 'View image'),
  'Copy Image': (PageMenuRole.copyImage, 'Copy image'),
  'Copy Image Address': (PageMenuRole.copyImageAddress, 'Copy image address'),
  'Save Image As…': (PageMenuRole.downloadImage, 'Download image'),
  'Play': (PageMenuRole.playPause, 'Play'),
  'Pause': (PageMenuRole.playPause, 'Pause'),
  'Mute': (PageMenuRole.mute, 'Mute'),
  'Unmute': (PageMenuRole.mute, 'Unmute'),
  'Show Controls': (PageMenuRole.controls, 'Show controls'),
  'Hide Controls': (PageMenuRole.controls, 'Hide controls'),
  'Loop': (PageMenuRole.loop, 'Loop'),
  'Full Screen': (PageMenuRole.fullscreen, 'Full screen'),
  'Exit Full Screen': (PageMenuRole.fullscreen, 'Exit full screen'),
  'Open Video in New Tab': (
    PageMenuRole.openMediaInNewTab,
    'Open video in new tab',
  ),
  'Open Audio in New Tab': (
    PageMenuRole.openMediaInNewTab,
    'Open audio in new tab',
  ),
  'Open Video': (PageMenuRole.openMedia, 'View video'),
  'Open Audio': (PageMenuRole.openMedia, 'Open audio'),
  'Copy Video Address': (PageMenuRole.copyMediaAddress, 'Copy video address'),
  'Copy Audio Address': (PageMenuRole.copyMediaAddress, 'Copy audio address'),
  'Cut': (PageMenuRole.cut, 'Cut'),
  'Copy': (PageMenuRole.copy, 'Copy'),
  'Paste': (PageMenuRole.paste, 'Paste'),
  'Paste and Match Style': (PageMenuRole.pastePlain, 'Paste as plain text'),
  'Select All': (PageMenuRole.selectAll, 'Select all'),
  'Ignore Spelling': (PageMenuRole.spelling, 'Ignore spelling'),
  'Learn Spelling': (PageMenuRole.spelling, 'Add to dictionary'),
};

// The order of the text toolbar, whose first few are the ones in view.
const List<PageMenuRole> _toolbarOrder = [
  PageMenuRole.cut,
  PageMenuRole.copy,
  PageMenuRole.paste,
  PageMenuRole.selectAll,
  PageMenuRole.search,
  PageMenuRole.openInNewTab,
  PageMenuRole.pastePlain,
  PageMenuRole.copyLinkToHighlight,
];

/// The menu to show for what the engine offers. [type] is the engine's word
/// for what was pressed on: `page`, `link`, `image` or `media`.
PageMenuPlan planPageMenu(String type, List<EngineMenuEntry> entries) {
  final items = <PageMenuItem>[];
  var group = 0;
  var groupHasItems = false;
  var hasTextEditing = false;

  void collect(List<EngineMenuEntry> list) {
    for (final entry in list) {
      if (entry.kind == 'separator') {
        if (groupHasItems) {
          group++;
          groupHasItems = false;
        }
        continue;
      }
      if (entry.kind == 'submenu') {
        collect(entry.items);
        continue;
      }
      final token = entry.token;
      if (token == null || _leftOut.contains(entry.label)) continue;

      final known = _known[entry.label];
      var role = known?.$1 ?? PageMenuRole.other;
      var label = known?.$2 ?? entry.label;
      // The engine words its search entry after the search engine and the
      // text, so it is known by how it begins.
      if (known == null && entry.label.startsWith('Search ')) {
        role = PageMenuRole.search;
        label = 'Search';
      }
      if (role == PageMenuRole.cut ||
          role == PageMenuRole.copy ||
          role == PageMenuRole.paste) {
        hasTextEditing = true;
      }
      // What cannot be done is not offered.
      if (!entry.enabled) continue;

      items.add(
        PageMenuItem(
          role: role,
          label: label,
          token: token,
          checked: entry.checkable ? entry.checked : null,
          group: group,
        ),
      );
      groupHasItems = true;
    }
  }

  collect(entries);
  if (items.isEmpty) return PageMenuPlan.nothing;

  bool has(PageMenuRole role) => items.any((item) => item.role == role);

  if (type == 'image' || has(PageMenuRole.openImageInNewTab)) {
    return PageMenuPlan(PageMenuStyle.card, PageMenuSubject.image, items);
  }
  if (type == 'media') {
    final audio = entries.any(
      (entry) =>
          entry.label == 'Open Audio in New Tab' ||
          entry.label == 'Copy Audio Address',
    );
    return PageMenuPlan(
      PageMenuStyle.card,
      audio ? PageMenuSubject.audio : PageMenuSubject.video,
      items,
    );
  }
  // Selected text that reads as an address is a "link" to the engine, but it
  // can still be copied, which a real link's menu cannot.
  if (type == 'link' && !hasTextEditing) {
    return PageMenuPlan(PageMenuStyle.card, PageMenuSubject.link, items);
  }

  final textual =
      hasTextEditing || has(PageMenuRole.selectAll) || has(PageMenuRole.search);
  if (!textual) return PageMenuPlan.nothing;

  int rank(PageMenuItem item) {
    final index = _toolbarOrder.indexOf(item.role);
    return index < 0 ? _toolbarOrder.length : index;
  }

  // A sort that keeps what ranks alike in the order the engine gave it.
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return PageMenuPlan(PageMenuStyle.toolbar, PageMenuSubject.text, [
    for (final (_, item) in indexed) item,
  ]);
}
