import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// How a permission of the engine is shown on a phone.
({String label, String action, IconData icon}) mobilePermissionKind(
  String name,
) => switch (name) {
  'geolocation' => (
    label: 'Location',
    action: 'know your location',
    icon: Icons.location_on_outlined,
  ),
  _ => (label: name, action: 'use "$name"', icon: Icons.shield_outlined),
};

/// The question a tab's page is waiting on, if any: may it have this?
class MobilePermissionPrompt extends StatelessWidget {
  const MobilePermissionPrompt({required this.viewId, super.key});

  final int viewId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LadybirdSiteBridge.instance,
      builder: (context, _) {
        final prompt = LadybirdSiteBridge.instance.promptFor(viewId);
        if (prompt == null) return const SizedBox.shrink();
        return _PromptCard(key: ValueKey(prompt.id), prompt: prompt);
      },
    );
  }
}

class _PromptCard extends StatefulWidget {
  const _PromptCard({required this.prompt, super.key});

  final PermissionPrompt prompt;

  @override
  State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  /// An answer is not taken the instant the card appears, so that a tap already
  /// on its way to the page cannot grant anything.
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

  VoidCallback? _decide(PermissionOutcome outcome) =>
      _ready ? () => _answer(outcome) : null;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final prompt = widget.prompt;
    final kind = mobilePermissionKind(prompt.name);
    final site = prompt.isFile
        ? 'This file'
        : prompt.origin.replaceFirst('https://', '');
    // Not a question: the system keeps this from the browser.
    final notice = prompt.isSystemDeniedNotice;

    return Material(
      color: colors.menu,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(kind.icon, color: colors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notice
                        ? 'Android does not let Rubisco ${kind.action}, so '
                              '$site cannot either.'
                        : '$site wants to ${kind.action}',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Not now',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _answer(
                    notice
                        ? PermissionOutcome.cancelled
                        : PermissionOutcome.dismissed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: notice
                  ? FilledButton(
                      onPressed: () => _answer(PermissionOutcome.cancelled),
                      child: const Text('OK'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: _decide(PermissionOutcome.allowAlways),
                          child: const Text('Allow while visiting the site'),
                        ),
                        FilledButton.tonal(
                          onPressed: _decide(PermissionOutcome.allowOnce),
                          child: const Text('Allow this time'),
                        ),
                        TextButton(
                          onPressed: _decide(PermissionOutcome.block),
                          child: const Text('Never allow'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
