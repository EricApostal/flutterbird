import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/extensions/extension_popup.dart';
import 'package:rubisco_browser/features/extensions/extension_toolbar.dart';
import 'package:rubisco_browser/features/extensions/extensions_menu.dart';
import 'package:rubisco_browser/features/extensions/extensions_panel.dart';

/// What hangs from the extensions button.
sealed class _Showing {
  const _Showing();
}

class _Menu extends _Showing {
  const _Menu();
}

class _Manage extends _Showing {
  const _Manage();
}

/// The popup of an extension that has no button of its own on the toolbar.
class _Popup extends _Showing {
  const _Popup(this.extension);

  final InstalledExtension extension;
}

/// The toolbar's extensions button, as in Firefox: every extension with a
/// button is in its menu, where it can be used, or pinned to the toolbar.
class ExtensionsButton extends ConsumerStatefulWidget {
  const ExtensionsButton({super.key});

  @override
  ConsumerState<ExtensionsButton> createState() => _ExtensionsButtonState();
}

class _ExtensionsButtonState extends ConsumerState<ExtensionsButton> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  StreamSubscription<String>? _popupRequests;
  _Showing _showing = const _Menu();

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  /// An extension that asks for its popup and is not pinned gets it from here.
  Future<void> _listen() async {
    final service = await ref.read(extensionServiceProvider.future);
    if (!mounted) return;
    _popupRequests = service.actions.popupRequests.listen((uuid) {
      if (!mounted || service.pins.isPinned(uuid)) return;
      if (!isToolbarOfKeyWindow(context, ref)) return;
      final extension = service.registry.byUuid(uuid);
      if (extension == null) return;
      final state = service.actions.stateFor(
        uuid,
        tabId: ref.read(browserBridgeProvider)?.activeTabId,
      );
      if (state.popup?.isNotEmpty ?? false) _show(_Popup(extension));
    });
  }

  @override
  void dispose() {
    unawaited(_popupRequests?.cancel());
    super.dispose();
  }

  void _show(_Showing showing) {
    setState(() => _showing = showing);
    if (!_overlayController.isShowing) _overlayController.show();
  }

  Widget _buildPanel(BuildContext context) {
    final service = ref.read(extensionServiceProvider).value;
    final child = switch (_showing) {
      _Menu() => ExtensionsMenu(
        onOpenPopup: (extension) => _show(_Popup(extension)),
        onManage: () => _show(const _Manage()),
        onClose: _overlayController.hide,
      ),
      _Manage() => ExtensionsPanel(onClose: _overlayController.hide),
      _Popup(:final extension) when service != null => ExtensionPopup(
        key: ValueKey(extension.uuid),
        url:
            '${extension.origin}/'
            '${service.actions.stateFor(extension.uuid, tabId: ref.read(browserBridgeProvider)?.activeTabId).popup}',
        contentSizes: service.host.contentSizes,
        onClose: _overlayController.hide,
      ),
      _Popup() => const SizedBox.shrink(),
    };

    return child;
  }

  @override
  Widget build(BuildContext context) {
    return BirdPopover(
      controller: _overlayController,
      align: BirdPopoverAlign.end,
      popoverBuilder: _buildPanel,
      child: BirdToolbarButton(
        glyph: BirdGlyph.extension,
        tooltip: 'Extensions',
        onPressed: () => _overlayController.isShowing
            ? _overlayController.hide()
            : _show(const _Menu()),
      ),
    );
  }
}
