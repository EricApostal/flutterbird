import 'package:bird_session/bird_session.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/permission_prompt_card.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_info_card.dart';
import 'package:ladybird/ladybird.dart';

/// The width the button takes at the start of the address field.
const double kSiteInfoButtonWidth = 38;

/// The button before the address: how the page got here at a glance, and on a
/// press what the site may do. A page that asks for a permission asks from
/// here.
class SiteInfoButton extends StatefulWidget {
  const SiteInfoButton({required this.tab, super.key});

  final LadybirdController tab;

  @override
  State<SiteInfoButton> createState() => _SiteInfoButtonState();
}

class _SiteInfoButtonState extends State<SiteInfoButton> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LadybirdSiteBridge _bridge = LadybirdSiteBridge.instance;

  /// The prompt this has already opened itself for, so that one the user put
  /// aside does not come back by itself.
  int? _openedFor;

  @override
  void initState() {
    super.initState();
    _bridge.addListener(_promptsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptsChanged());
  }

  @override
  void didUpdateWidget(SiteInfoButton old) {
    super.didUpdateWidget(old);
    if (old.tab.viewId == widget.tab.viewId) return;
    // Another tab's panel is about another site.
    _openedFor = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hide();
      _promptsChanged();
    });
  }

  @override
  void dispose() {
    _bridge.removeListener(_promptsChanged);
    super.dispose();
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  void _promptsChanged() {
    if (!mounted) return;
    final prompt = _bridge.promptFor(widget.tab.viewId);
    if (prompt != null && prompt.id != _openedFor) {
      _openedFor = prompt.id;
      if (!_overlay.isShowing) _overlay.show();
    } else if (prompt == null && _openedFor != null) {
      _openedFor = null;
      _hide();
    }
    setState(() {});
  }

  static (BirdGlyph, String?) _look(SiteSecurityKind kind) => switch (kind) {
    SiteSecurityKind.https => (BirdGlyph.lock, null),
    SiteSecurityKind.insecure => (BirdGlyph.lockOff, 'Not secure'),
    SiteSecurityKind.local => (BirdGlyph.info, null),
    SiteSecurityKind.file => (BirdGlyph.file, null),
    SiteSecurityKind.extension => (BirdGlyph.extension, null),
    SiteSecurityKind.internal => (BirdGlyph.globe, null),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;

    return BirdPopover(
      controller: _overlay,
      gap: 8,
      // A prompt opens by itself, and must not take what is being typed. A
      // press anywhere else puts the panel away; a prompt stays asked, and
      // the button brings it back.
      takeFocus: false,
      popoverBuilder: _buildPanel,
      child: ValueListenableBuilder<String>(
        valueListenable: widget.tab.urlNotifier,
        builder: (context, url, _) {
          final (glyph, warning) = _look(SiteSecurity.of(url).kind);
          final waiting = _bridge.promptFor(widget.tab.viewId) != null;
          // Filled in would say it holds something; a lit one asks to be
          // looked at.
          final asking = waiting ? colors.link : null;
          return BirdToolbarButton(
            glyph: waiting ? BirdGlyph.help : glyph,
            tooltip: waiting
                ? 'This site is asking for a permission'
                : warning ?? 'Site information',
            size: 26,
            iconSize: 15,
            color:
                asking ??
                (warning != null ? colors.danger : colors.textSecondary),
            onPressed: () {
              setState(_overlay.toggle);
            },
          );
        },
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: _bridge,
      builder: (context, _) {
        final prompt = _bridge.promptFor(widget.tab.viewId);
        return prompt != null
            ? PermissionPromptCard(key: ValueKey(prompt.id), prompt: prompt)
            : SiteInfoCard(tab: widget.tab);
      },
    );
  }
}
