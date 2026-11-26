import 'package:bird_session/bird_session.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/state/find_in_page.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

const double kMobileFindBarHeight = 56;

/// Find in page, across the top of the screen as in Chrome.
class MobileFindBar extends StatefulWidget {
  const MobileFindBar({required this.tab, super.key});

  final LadybirdController tab;

  @override
  State<MobileFindBar> createState() => _MobileFindBarState();
}

class _MobileFindBarState extends State<MobileFindBar> {
  final FindInPage _search = FindInPage.instance;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'Find in page');
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
    _focus.unfocus();
    _search.close(_viewId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Material(
      color: colors.surface,
      elevation: 3,
      shadowColor: Colors.black45,
      child: SizedBox(
        height: kMobileFindBarHeight,
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
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontSize: 16, color: colors.text),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Find in page',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        color: colors.textSecondary,
                      ),
                    ),
                    onChanged: (value) => _search.search(_viewId, value),
                    // Searching again goes to the next match and keeps the
                    // keyboard.
                    onEditingComplete: () =>
                        _search.step(_viewId, forwards: true),
                    onTapOutside: (_) {},
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  findCountLabel(
                    query: query,
                    current: result?.current ?? 0,
                    total: total,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: total == 0 ? colors.danger : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Container(width: 1, height: 24, color: colors.divider),
                IconButton(
                  tooltip: 'Previous match',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: canStep
                      ? () => _search.step(_viewId, forwards: false)
                      : null,
                ),
                IconButton(
                  tooltip: 'Next match',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: canStep
                      ? () => _search.step(_viewId, forwards: true)
                      : null,
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
