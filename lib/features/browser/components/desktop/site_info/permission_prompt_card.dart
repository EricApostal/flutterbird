import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/permission_kinds.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_card.dart';
import 'package:ladybird/ladybird.dart';

/// A site's question: may it have this?
class PermissionPromptCard extends StatefulWidget {
  const PermissionPromptCard({required this.prompt, super.key});

  final PermissionPrompt prompt;

  @override
  State<PermissionPromptCard> createState() => _PermissionPromptCardState();
}

class _PermissionPromptCardState extends State<PermissionPromptCard> {
  /// An answer is not taken the instant the prompt appears, so that a click
  /// already on its way to the page cannot grant anything.
  static const _settleTime = Duration(milliseconds: 500);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    LadybirdSiteBridge.instance.markShown(widget.prompt.id);
    Future<void>.delayed(_settleTime, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _answer(PermissionOutcome outcome) {
    LadybirdSiteBridge.instance.respond(widget.prompt.id, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.prompt;
    final kind = PermissionKind.of(prompt.name);
    final site = prompt.isFile ? 'This file' : prompt.origin;

    return SiteCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: BirdIcon(kind.glyph, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prompt.isSystemDeniedNotice
                      ? 'macOS does not let Rubisco Browser ${kind.action}, so '
                            '$site cannot either. You can change this in '
                            'System Settings.'
                      : '$site wants to ${kind.action}',
                  style: context.birdText(weight: FontWeight.w600),
                ),
              ),
              BirdToolbarButton(
                glyph: BirdGlyph.close,
                tooltip: 'Not now',
                size: 22,
                iconSize: 10,
                onPressed: () => _answer(
                  prompt.isSystemDeniedNotice
                      ? PermissionOutcome.cancelled
                      : PermissionOutcome.dismissed,
                ),
              ),
            ],
          ),
          if (prompt.showOsHint && !prompt.isSystemDeniedNotice) ...[
            const SizedBox(height: 6),
            Text(
              'macOS may ask you as well.',
              style: context.birdText(
                color: context.bird.textSecondary,
                size: BirdTextSize.small,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (prompt.isSystemDeniedNotice)
            BirdButton.primary(
              'OK',
              expand: true,
              onPressed: () => _answer(PermissionOutcome.cancelled),
            )
          else ...[
            BirdButton.primary(
              'Allow while visiting the site',
              expand: true,
              onPressed: _ready
                  ? () => _answer(PermissionOutcome.allowAlways)
                  : null,
            ),
            BirdButton(
              'Allow this time',
              expand: true,
              onPressed: _ready
                  ? () => _answer(PermissionOutcome.allowOnce)
                  : null,
            ),
            BirdButton(
              'Never allow',
              expand: true,
              onPressed: _ready ? () => _answer(PermissionOutcome.block) : null,
            ),
          ],
        ],
      ),
    );
  }
}
