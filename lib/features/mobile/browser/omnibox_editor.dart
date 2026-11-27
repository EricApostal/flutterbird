import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_toolbar.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

const double _fieldHeight = kMobileToolbarHeight;

/// The address bar while it is being typed in: the field grows out of the
/// toolbar, and what it suggests fills the screen behind it.
///
/// With the bar at the bottom the list runs upwards, so that the best
/// suggestion is next to the thumb that is typing.
class OmniboxEditor extends ConsumerStatefulWidget {
  const OmniboxEditor({
    required this.tab,
    required this.position,
    required this.animation,
    required this.onClose,
    required this.onNavigate,
    super.key,
  });

  final LadybirdController tab;
  final AddressBarPosition position;

  /// From 0, the toolbar, to 1, the editor.
  final Animation<double> animation;
  final VoidCallback onClose;

  /// Where what was typed or chosen leads.
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<OmniboxEditor> createState() => _OmniboxEditorState();
}

class _OmniboxEditorState extends ConsumerState<OmniboxEditor> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'Address bar');

  /// The address of the page being left, or empty where it has none to show.
  late final String _pageUrl;

  /// Whether the field holds something the user typed, rather than the address
  /// it was filled with.
  bool _edited = false;
  List<OmniboxSuggestion> _rows = const [];
  List<VisitedPage> _history = const [];

  BrowserOmnibox get _omnibox => ref.read(browserOmniboxProvider.notifier);

  @override
  void initState() {
    super.initState();
    final url = widget.tab.urlNotifier.value;
    _pageUrl = widget.tab.isOnNewTabPage || !isShareableUrl(url) ? '' : url;
    _text = TextEditingController(text: _pageUrl)
      ..selection = TextSelection(baseOffset: 0, extentOffset: _pageUrl.length);

    // Not while widgets are being built, when providers cannot change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Asked for outright: the page has the focus, and autofocus only takes
      // it when nothing does.
      _focus.requestFocus();
      _omnibox.refreshBookmarks(widget.tab);
      setState(() {
        _history = parseVisitedPages(historyEntriesJson(limit: 200));
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {
      _edited = true;
      _rows = value.trim().isEmpty
          ? const []
          : _omnibox.propose(widget.tab, value, complete: false).rows;
    });
  }

  void _submit(String value) {
    if (value.trim().isEmpty) {
      widget.onClose();
      return;
    }
    widget.onNavigate(_omnibox.buildNavigationTarget(widget.tab, value.trim()));
  }

  void _choose(OmniboxSuggestion suggestion) {
    widget.onNavigate(
      suggestion.isSearch
          ? _omnibox.buildNavigationTarget(widget.tab, suggestion.value)
          : suggestion.value,
    );
  }

  /// Puts a suggestion in the field, to be added to.
  void _refine(String value) {
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _changed(value);
    _focus.requestFocus();
  }

  void _editPageUrl() {
    _text.value = TextEditingValue(
      text: _pageUrl,
      selection: TextSelection.collapsed(offset: _pageUrl.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final media = MediaQuery.of(context);
    final atBottom = widget.position == AddressBarPosition.bottom;
    final bottom = math.max(media.viewInsets.bottom, media.viewPadding.bottom);
    final entering = widget.animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );

    final list = Expanded(
      child: FadeTransition(
        opacity: entering,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, atBottom ? 0.04 : -0.04),
            end: Offset.zero,
          ).animate(entering),
          child: _suggestions(atBottom),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: entering,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: ColoredBox(color: colors.surface),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: media.viewPadding.top,
            left: media.viewPadding.left,
            right: media.viewPadding.right,
            bottom: bottom,
          ),
          // So that ink shows over the background rather than under it.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                if (!atBottom) _field(entering),
                list,
                if (atBottom) _field(entering),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(Animation<double> entering) {
    final colors = context.mobile;
    return SizedBox(
      height: _fieldHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final toolbar = mobileAddressInsets(constraints.maxWidth);
          return AnimatedBuilder(
            animation: entering,
            builder: (context, field) {
              final t = entering.value;
              final left = _lerp(toolbar.left, 52, t);
              final right = _lerp(toolbar.right, 10, t);
              return Stack(
                children: [
                  Positioned(
                    left: 2,
                    top: (_fieldHeight - 48) / 2,
                    child: Opacity(
                      opacity: t,
                      child: IconButton(
                        tooltip: 'Back',
                        icon: Icon(Icons.arrow_back, color: colors.text),
                        onPressed: widget.onClose,
                      ),
                    ),
                  ),
                  Positioned(
                    left: left,
                    right: right,
                    top: (_fieldHeight - kMobileAddressHeight) / 2,
                    height: kMobileAddressHeight + 2 * t,
                    child: field!,
                  ),
                ],
              );
            },
            child: _input(),
          );
        },
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  Widget _input() {
    final colors = context.mobile;
    return Material(
      color: colors.field,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search, size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autocorrect: false,
              // Suggestions stay on: turning them off tells Android's keyboard
              // that this is a visible password, and not an address.
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              style: TextStyle(fontSize: 16, color: colors.text),
              decoration: InputDecoration.collapsed(
                hintText: 'Search or type URL',
                hintStyle: TextStyle(fontSize: 16, color: colors.textSecondary),
              ),
              onChanged: _changed,
              onSubmitted: _submit,
              // A tap on a suggestion must not take the keyboard away before
              // the suggestion has been taken.
              onTapOutside: (_) {},
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 14)
                : IconButton(
                    tooltip: 'Clear',
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () {
                      _text.clear();
                      _changed('');
                      _focus.requestFocus();
                    },
                  ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _suggestions(bool atBottom) {
    final query = _text.text;
    // With the bar at the bottom the list is turned over, so the first of
    // these is the one nearest the field either way.
    final items = _edited && query.trim().isNotEmpty
        ? [
            for (final row in _rows)
              _SuggestionRow(
                suggestion: row,
                query: query,
                atBottom: atBottom,
                onTap: () => _choose(row),
                onRefine: () => _refine(row.value),
              ),
          ]
        : _beforeTyping(atBottom);

    return ListView(
      reverse: atBottom,
      padding: const EdgeInsets.symmetric(vertical: 6),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: items,
    );
  }

  List<Widget> _beforeTyping(bool atBottom) {
    final sites = frequentSites(_history, now: DateTime.now(), limit: 8);
    final recent = recentPages(_history, limit: 6);
    return [
      if (_pageUrl.isNotEmpty)
        _CurrentPageRow(
          tab: widget.tab,
          url: _pageUrl,
          onTap: () => widget.onNavigate(_pageUrl),
          onEdit: _editPageUrl,
        ),
      if (sites.isNotEmpty)
        SizedBox(
          height: 92,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final site = sites[index];
              return _SiteChip(
                label: site.host,
                url: site.url,
                favicon: site.favicon,
                onTap: () => widget.onNavigate(site.url),
              );
            },
          ),
        ),
      for (final page in recent)
        if (page.url != _pageUrl)
          _SuggestionRow(
            suggestion: OmniboxSuggestion(
              type: OmniboxSuggestionType.history,
              title: pageTitle(page.title, page.url),
              value: page.url,
              favicon: page.favicon,
            ),
            query: '',
            atBottom: atBottom,
            onTap: () => widget.onNavigate(page.url),
            onRefine: () => _refine(page.url),
          ),
    ];
  }
}

/// The page being left, to share or copy its address, or to edit it.
class _CurrentPageRow extends StatelessWidget {
  const _CurrentPageRow({
    required this.tab,
    required this.url,
    required this.onTap,
    required this.onEdit,
  });

  final LadybirdController tab;
  final String url;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 4, 8),
        child: Row(
          children: [
            TabIcon(tab: tab, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabTitle(tab),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, color: colors.text),
                  ),
                  Text(
                    displayAddress(url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.link),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Share',
              iconSize: 21,
              icon: Icon(Icons.share_outlined, color: colors.textSecondary),
              onPressed: () => shareText(context, url),
            ),
            IconButton(
              tooltip: 'Copy link',
              iconSize: 21,
              icon: Icon(Icons.copy_rounded, color: colors.textSecondary),
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            ),
            IconButton(
              tooltip: 'Edit',
              iconSize: 21,
              icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteChip extends StatelessWidget {
  const _SiteChip({
    required this.label,
    required this.url,
    required this.favicon,
    required this.onTap,
  });

  final String label;
  final String url;
  final String? favicon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.container,
                shape: BoxShape.circle,
              ),
              child: SiteIcon(url: url, favicon: favicon, size: 24),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.query,
    required this.atBottom,
    required this.onTap,
    required this.onRefine,
  });

  final OmniboxSuggestion suggestion;
  final String query;
  final bool atBottom;
  final VoidCallback onTap;
  final VoidCallback onRefine;

  /// [text] with what was asked for set in bold.
  TextSpan _marked(String text, TextStyle style) {
    final ranges = matchRanges(text, query);
    if (ranges.isEmpty) return TextSpan(text: text, style: style);
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    var at = 0;
    for (final range in ranges) {
      if (range.start > at) {
        spans.add(TextSpan(text: text.substring(at, range.start)));
      }
      spans.add(
        TextSpan(text: text.substring(range.start, range.end), style: bold),
      );
      at = range.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final isAddress = suggestion.type == OmniboxSuggestionType.address;
    final isSearch = suggestion.isSearch;
    final shown = displayAddress(suggestion.value);
    final title = isSearch
        ? suggestion.value
        : (isAddress || suggestion.title.isEmpty ? shown : suggestion.title);
    final subtitle = isSearch
        ? suggestion.subtitle
        : (isAddress ? null : shown);

    final icon = switch (suggestion.type) {
      OmniboxSuggestionType.searchAction ||
      OmniboxSuggestionType.searchQuery => Icons.search,
      OmniboxSuggestionType.history => Icons.history,
      OmniboxSuggestionType.bookmark => Icons.star_rounded,
      OmniboxSuggestionType.address => Icons.public,
    };

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.container,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: suggestion.favicon != null && !isSearch
                    ? SiteIcon(
                        url: suggestion.value,
                        favicon: suggestion.favicon,
                        size: 20,
                      )
                    : Icon(icon, size: 20, color: colors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      _marked(
                        title,
                        TextStyle(fontSize: 16, color: colors.text),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isSearch ? colors.textSecondary : colors.link,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Put in the address bar',
                iconSize: 20,
                icon: Icon(
                  atBottom ? Icons.south_west : Icons.north_west,
                  color: colors.textSecondary,
                ),
                onPressed: onRefine,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
