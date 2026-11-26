import 'package:bird_session/bird_session.dart';
import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/site_info/permission_prompt_card.dart';
import 'package:flutterbird/features/browser/components/desktop/site_info/site_info_card.dart';
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
  final LayerLink _link = LayerLink();
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

  static (IconData, String?) _look(SiteSecurityKind kind) => switch (kind) {
    SiteSecurityKind.https => (Icons.lock_outline, null),
    SiteSecurityKind.insecure => (Icons.no_encryption_outlined, 'Not secure'),
    SiteSecurityKind.local => (Icons.info_outline, null),
    SiteSecurityKind.file => (Icons.insert_drive_file_outlined, null),
    SiteSecurityKind.extension => (Icons.extension_outlined, null),
    SiteSecurityKind.internal => (Icons.public, null),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: _buildPanel,
        child: ValueListenableBuilder<String>(
          valueListenable: widget.tab.urlNotifier,
          builder: (context, url, _) {
            final (icon, warning) = _look(SiteSecurity.of(url).kind);
            final waiting = _bridge.promptFor(widget.tab.viewId) != null;
            return IconButton(
              tooltip: waiting
                  ? 'This site is asking for a permission'
                  : warning ?? 'Site information',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: kSiteInfoButtonWidth,
                height: 30,
              ),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(_overlay.toggle);
              },
              icon: Icon(
                waiting ? Icons.live_help_outlined : icon,
                color: waiting
                    ? theme.colorScheme.primary
                    : warning != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // A press anywhere else puts the panel away. A prompt stays asked:
          // the button brings it back.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hide,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 8),
            child: Align(
              alignment: Alignment.topLeft,
              // A text field lies under the button, and a press in the panel
              // is none of its business.
              child: TextFieldTapRegion(
                child: ListenableBuilder(
                  listenable: _bridge,
                  builder: (context, _) {
                    final prompt = _bridge.promptFor(widget.tab.viewId);
                    return prompt != null
                        ? PermissionPromptCard(
                            key: ValueKey(prompt.id),
                            prompt: prompt,
                          )
                        : SiteInfoCard(tab: widget.tab);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
