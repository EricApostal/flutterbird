import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/tabs/tab_snapshot.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

const double kTabCardHeader = 40;
const double kTabCardInset = 4;
const double kTabCardRadius = 16;
const double kTabThumbnailRadius = 12;

/// A tab in the switcher: its name over a picture of its page.
class MobileTabCard extends StatelessWidget {
  const MobileTabCard({
    required this.tab,
    required this.selected,
    required this.lifted,
    required this.onClose,
    super.key,
  });

  final LadybirdController tab;

  /// Whether it is the tab that was on screen.
  final bool selected;

  /// Whether it is being dragged to another place.
  final bool lifted;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final foreground = selected ? colors.onAccent : colors.text;
    return Material(
      color: selected ? colors.accent : colors.containerHigh,
      elevation: lifted ? 10 : 0,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(kTabCardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: kTabCardHeader,
            child: Row(
              children: [
                const SizedBox(width: 12),
                TabIcon(tab: tab, size: 16, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      tab.titleNotifier,
                      tab.urlNotifier,
                    ]),
                    builder: (context, _) => Text(
                      tabTitle(tab),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Semantics(
                    button: true,
                    label: 'Close tab',
                    child: InkResponse(
                      onTap: onClose,
                      radius: 20,
                      child: Icon(Icons.close, size: 18, color: foreground),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kTabCardInset,
                0,
                kTabCardInset,
                kTabCardInset,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kTabThumbnailRadius),
                child: TabSnapshot(tab: tab),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
