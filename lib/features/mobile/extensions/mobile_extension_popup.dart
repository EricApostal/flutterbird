import 'dart:async';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_icon.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';

const double _minimumPopupHeight = 240;

/// Shows an extension's popup in a sheet from the bottom of the screen.
Future<void> showMobileExtensionPopup(
  BuildContext context, {
  required ExtensionService service,
  required BrowserBridge? bridge,
  required InstalledExtension extension,
}) async {
  final state = service.actions.stateFor(
    extension.uuid,
    tabId: bridge?.activeTabId,
  );
  final popup = state.popup;
  if (popup == null || popup.isEmpty) return;
  final path = popup.startsWith('/') ? popup.substring(1) : popup;

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    // A drag on the page is the page's, to scroll with.
    enableDrag: false,
    builder: (context) => _PopupSheet(
      service: service,
      bridge: bridge,
      extension: extension,
      url: '${extension.origin}/$path',
    ),
  );
}

class _PopupSheet extends StatefulWidget {
  const _PopupSheet({
    required this.service,
    required this.bridge,
    required this.extension,
    required this.url,
  });

  final ExtensionService service;
  final BrowserBridge? bridge;
  final InstalledExtension extension;
  final String url;

  @override
  State<_PopupSheet> createState() => _PopupSheetState();
}

class _PopupSheetState extends State<_PopupSheet> {
  late final LadybirdController _controller;
  StreamSubscription<ExtensionContentSize>? _sizes;
  StreamSubscription<TabEvent>? _tabs;
  Timer? _giveUp;
  bool _closed = false;

  // The page is laid out in all the room there is, out of sight, and the sheet
  // then takes what it used, or all of it if the page never says.
  bool _measured = false;
  double? _contentHeight;

  @override
  void initState() {
    super.initState();
    _controller = LadybirdController();
    // Extensions' popups close themselves once they have done their job.
    _controller.onCloseRequested = _close;
    _controller.navigate(widget.url);

    _sizes = widget.service.host.contentSizes.listen((size) {
      if (size.context.viewId != _controller.viewId || !mounted) return;
      setState(() {
        _measured = true;
        _contentHeight = size.height;
      });
    });
    // An extension that goes to a tab, as one opening its settings does, is
    // done with its popup, and with whatever is over the tab.
    _tabs = widget.bridge?.tabEvents.listen((event) {
      if (event is! TabActivated || _closed || !mounted) return;
      _closed = true;
      closeMobileOverlays(Navigator.of(context, rootNavigator: true));
    });
    _giveUp = Timer(const Duration(seconds: 3), () {
      if (mounted && !_measured) setState(() => _measured = true);
    });
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _sizes?.cancel();
    _tabs?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    // It slides away where nothing is over it.
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final room = math.max(
      _minimumPopupHeight,
      math.min(media.size.height * 0.75, media.size.height - keyboard - 140),
    );
    final height = (_contentHeight ?? room).clamp(_minimumPopupHeight, room);

    return Padding(
      padding: EdgeInsets.only(
        bottom: math.max(keyboard, media.viewPadding.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
            child: Row(
              children: [
                MobileExtensionIcon(
                  service: widget.service,
                  extension: widget.extension,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.extension.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: context.mobile.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            ),
          ),
          SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: _measured ? 1 : 0,
                  child: LadybirdView(controller: _controller),
                ),
                if (!_measured)
                  const Center(child: CircularProgressIndicator.adaptive()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
