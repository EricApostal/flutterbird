import 'package:bird_session/bird_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ladybird/ladybird.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:rubisco_browser/features/browser/state/find_in_page.dart';

/// A page, with its find bar over the top right corner while it is open.
class FindBarLayer extends StatelessWidget {
  const FindBarLayer({required this.tab, required this.child, super.key});

  final LadybirdController tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Always a stack, so that opening the bar does not move the page about in
    // the widget tree.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        ListenableBuilder(
          listenable: FindInPage.instance,
          builder: (context, _) => FindInPage.instance.isOpen(tab.viewId)
              ? Positioned(
                  top: 6,
                  right: 16,
                  child: _FindBar(key: ValueKey(tab.viewId), tab: tab),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _FindBar extends StatefulWidget {
  const _FindBar({required this.tab, super.key});

  final LadybirdController tab;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  final FindInPage _search = FindInPage.instance;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  late String _url;
  int _focusRequests = 0;

  int get _viewId => widget.tab.viewId;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _search.queryOf(_viewId));
    _url = widget.tab.urlNotifier.value;
    widget.tab.urlNotifier.addListener(_urlChanged);
    _search.addListener(_searchChanged);
    _searchChanged();
  }

  @override
  void dispose() {
    widget.tab.urlNotifier.removeListener(_urlChanged);
    _search.removeListener(_searchChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The bar goes when the page it searched does.
  void _urlChanged() {
    final url = widget.tab.urlNotifier.value;
    final samePage = isSamePageForFind(_url, url);
    _url = url;
    if (!samePage) _search.close(_viewId);
  }

  void _searchChanged() {
    final requests = _search.focusRequestsOf(_viewId);
    if (requests == _focusRequests) return;
    _focusRequests = requests;
    // Once the field is there to take it. The words are selected, so that
    // typing replaces them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _close() {
    // The keyboard goes back to where it was, which is usually the page.
    _focus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    _search.close(_viewId);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // An input method composing a word has its own use for these.
    if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _search.step(
        _viewId,
        forwards: !HardwareKeyboard.instance.isShiftPressed,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _button(String tooltip, IconData icon, VoidCallback? onPressed) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: omniboxSurfaceColor(theme),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      child: SizedBox(
        width: 360,
        height: 46,
        child: ValueListenableBuilder<FindResult?>(
          valueListenable: LadybirdFind.instance.results(_viewId),
          builder: (context, result, _) {
            final query = _search.queryOf(_viewId);
            final total = result == null || result.total < 0
                ? null
                : result.total;
            final canStep = query.isNotEmpty && total != 0;

            return Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _key,
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (value) => _search.search(_viewId, value),
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: 'Find in page',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Text(
                  findCountLabel(
                    query: query,
                    current: result?.current ?? 0,
                    total: total,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: total == 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 22,
                  child: VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.onSurface.withAlpha(50),
                  ),
                ),
                const SizedBox(width: 2),
                _button(
                  'Previous match',
                  Icons.keyboard_arrow_up,
                  canStep
                      ? () => _search.step(_viewId, forwards: false)
                      : null,
                ),
                _button(
                  'Next match',
                  Icons.keyboard_arrow_down,
                  canStep
                      ? () => _search.step(_viewId, forwards: true)
                      : null,
                ),
                _button('Close', Icons.close, _close),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
      ),
    );
  }
}
