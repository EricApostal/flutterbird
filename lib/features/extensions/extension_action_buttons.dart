import 'dart:async';
import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/extensions/extension_popup.dart';
import 'package:flutterbird/features/windows/window_scope.dart';

/// The toolbar buttons of the extensions that have one, as they are in
/// Firefox: the extension's icon, with the badge it set on top.
class ExtensionActionButtons extends ConsumerWidget {
  const ExtensionActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionActionsProvider).value ?? const [];
    if (extensions.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final extension in extensions) _ActionButton(extension: extension),
      ],
    );
  }
}

class _ActionButton extends ConsumerStatefulWidget {
  const _ActionButton({required this.extension});

  final InstalledExtension extension;

  @override
  ConsumerState<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends ConsumerState<_ActionButton> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  late int _windowId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _windowId = BrowserWindowScope.of(context);
  }

  /// The tab this button's window is showing. What a button shows, and what
  /// pressing it acts on, is about that tab, whichever window is focused.
  int? get _tabId =>
      ref.read(browserSessionProvider).window(_windowId)?.activeTabId;

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  /// The button changes when the extension changes it, and when the tab
  /// showing changes, since what it shows can be set per tab.
  Future<void> _listen() async {
    final service = await ref.read(extensionServiceProvider.future);
    if (!mounted) return;

    void refresh([Object? _]) {
      if (mounted) setState(() {});
    }

    _subscriptions.add(
      service.actions.changes
          .where((uuid) => uuid == widget.extension.uuid)
          .listen(refresh),
    );
    // An extension can open its own popup, as a password manager does when it
    // needs to be unlocked.
    _subscriptions.add(
      service.actions.popupRequests
          .where((uuid) => uuid == widget.extension.uuid)
          .listen((_) {
            if (!mounted) return;
            // Every window has this button, and the popup opens in one: the
            // browser window used last.
            final current = ref
                .read(browserSessionProvider)
                .lastFocused(kind: BrowserWindowKind.normal);
            if (current?.id != _windowId) return;
            final state = service.actions.stateFor(
              widget.extension.uuid,
              tabId: _tabId,
            );
            if (state.popup != null && state.popup!.isNotEmpty) {
              _overlay.show();
            }
          }),
    );
    final bridge = ref.read(browserBridgeProvider);
    if (bridge != null) _subscriptions.add(bridge.tabEvents.listen(refresh));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _pressed(ExtensionService service, ActionState state) async {
    final bridge = ref.read(browserBridgeProvider);
    final tabId = _tabId;

    if (state.popup != null && state.popup!.isNotEmpty) {
      _overlay.toggle();
      return;
    }

    // No popup: the extension handles the press itself.
    final tab = tabId == null ? null : bridge?.tab(tabId);
    ActionApi.notifyClicked(
      service.host,
      widget.extension,
      tab?.toJson(includeIdentity: true) ?? {'id': tabId ?? -1},
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(extensionServiceProvider).value;
    if (service == null) return const SizedBox.shrink();

    final extension = widget.extension;
    final tabId = ref.watch(browserWindowProvider(_windowId))?.activeTabId;
    final state = service.actions.stateFor(extension.uuid, tabId: tabId);

    final badge = state.badgeText ?? '';
    final badgeColor = state.badgeBackground;
    final enabled = state.enabled ?? true;

    final iconPath = state.iconPath;
    final icon = iconPath == null
        ? const Icon(Icons.extension_outlined, size: 20)
        : Image.file(
            File('${service.registry.directoryFor(extension).path}/$iconPath'),
            width: 20,
            height: 20,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.extension_outlined, size: 20),
          );

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) {
          return Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _overlay.hide,
              child: CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8),
                child: Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {}, // swallow so it doesn't bubble to the barrier
                    child: ExtensionPopup(
                      url: '${extension.origin}/${state.popup}',
                      contentSizes: service.host.contentSizes,
                      onClose: _overlay.hide,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: IconButton(
          tooltip: state.title ?? extension.name,
          onPressed: enabled ? () => _pressed(service, state) : null,
          icon: Badge(
            isLabelVisible: badge.isNotEmpty,
            label: Text(badge, style: const TextStyle(fontSize: 9)),
            backgroundColor: badgeColor == null
                ? null
                : Color.fromARGB(
                    badgeColor[3],
                    badgeColor[0],
                    badgeColor[1],
                    badgeColor[2],
                  ),
            child: Opacity(opacity: enabled ? 1 : 0.4, child: icon),
          ),
        ),
      ),
    );
  }
}
