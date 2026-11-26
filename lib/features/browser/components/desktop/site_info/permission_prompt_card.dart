import 'package:flutter/material.dart';
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
    final theme = Theme.of(context);
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
              Icon(kind.icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prompt.isSystemDeniedNotice
                      ? 'macOS does not let Rubisco Browser ${kind.action}, so '
                            '$site cannot either. You can change this in '
                            'System Settings.'
                      : '$site wants to ${kind.action}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Not now',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
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
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          if (prompt.isSystemDeniedNotice)
            FilledButton(
              onPressed: () => _answer(PermissionOutcome.cancelled),
              child: const Text('OK'),
            )
          else ...[
            FilledButton(
              onPressed: _ready
                  ? () => _answer(PermissionOutcome.allowAlways)
                  : null,
              child: const Text('Allow while visiting the site'),
            ),
            const SizedBox(height: 6),
            FilledButton.tonal(
              onPressed: _ready
                  ? () => _answer(PermissionOutcome.allowOnce)
                  : null,
              child: const Text('Allow this time'),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _ready ? () => _answer(PermissionOutcome.block) : null,
              child: const Text('Never allow'),
            ),
          ],
        ],
      ),
    );
  }
}
