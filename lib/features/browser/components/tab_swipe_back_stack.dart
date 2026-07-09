import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/browser/state/history_bitmap_cache.dart';
import 'package:flutterbird/features/browser/state/tab_history.dart';
import 'package:ladybird/ladybird.dart';

// Drives real Flutter Navigator page-route machinery from a tab's session
// history mirror (TabHistoryController, which itself only ever mirrors
// LadybirdController.sessionHistoryNotifier -- Ladybird's own truth). Each
// non-current entry renders as a frozen bitmap of the last time it was on
// screen; only the current entry renders the live engine view, via the same
// GlobalObjectKey<State<BrowserWindow>>(viewId) used everywhere else in the
// app, so it reparents between page slots instead of being recreated.
//
// Using CupertinoPage/MaterialPage (rather than a hand-rolled transition)
// means iOS gets its real interactive edge-swipe-to-pop and Android gets
// real OS predictive-back preview for free.
class TabSwipeBackStack extends ConsumerWidget {
  final int viewId;

  const TabSwipeBackStack({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(tabHistoryControllerProvider(viewId));
    final isFullscreen = ref.watch(browserFullscreenModeControllerProvider);

    // historyState.entries is already sorted by step (TabHistoryController
    // sorts once on the way in, so this stays consistent with
    // canPopFrom/goBack, which are also positional over the same order).
    final entries = historyState.entries;
    final currentStep = historyState.effectiveCurrentStep;
    final currentIndex = currentStep == null
        ? -1
        : entries.indexWhere((entry) => entry.step == currentStep);
    final visibleEntries = currentIndex < 0
        ? const <LadybirdSessionHistoryEntry>[]
        : entries.sublist(0, currentIndex + 1);
    final isConfirmedLive = historyState.optimisticCurrentStep == null;

    final pages = visibleEntries.isEmpty
        ? [
            _buildPage(
              key: const ValueKey('live-only'),
              canPop: false,
              child: BrowserWindow(
                key: GlobalObjectKey<State<BrowserWindow>>(viewId),
                viewId: viewId,
              ),
            ),
          ]
        : [
            for (var i = 0; i < visibleEntries.length; i++)
              _buildPage(
                key: ValueKey(visibleEntries[i].step),
                canPop:
                    !isFullscreen &&
                    historyState.canPopFrom(visibleEntries[i].step),
                child: i == visibleEntries.length - 1 && isConfirmedLive
                    ? BrowserWindow(
                        key: GlobalObjectKey<State<BrowserWindow>>(viewId),
                        viewId: viewId,
                      )
                    : _HistorySnapshotPage(
                        viewId: viewId,
                        entry: visibleEntries[i],
                        meta: historyState.meta[visibleEntries[i].step],
                      ),
              ),
          ];

    return Navigator(
      pages: pages,
      onDidRemovePage: (page) {
        ref.read(tabHistoryControllerProvider(viewId).notifier).goBack();
      },
    );
  }

  Page<void> _buildPage({
    required LocalKey key,
    required bool canPop,
    required Widget child,
  }) {
    if (Platform.isIOS) {
      return CupertinoPage<void>(key: key, canPop: canPop, child: child);
    }
    return MaterialPage<void>(key: key, canPop: canPop, child: child);
  }
}

class _HistorySnapshotPage extends StatefulWidget {
  const _HistorySnapshotPage({
    required this.viewId,
    required this.entry,
    required this.meta,
  });

  final int viewId;
  final LadybirdSessionHistoryEntry entry;
  final TabHistoryEntryMeta? meta;

  @override
  State<_HistorySnapshotPage> createState() => _HistorySnapshotPageState();
}

class _HistorySnapshotPageState extends State<_HistorySnapshotPage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _HistorySnapshotPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId ||
        oldWidget.entry.step != widget.entry.step) {
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final image = await HistoryBitmapCache.instance.load(
      widget.viewId,
      widget.entry.step,
    );
    if (!mounted) return;
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return SizedBox.expand(
        child: RawImage(
          image: image,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      );
    }

    return _HistoryPlaceholder(entry: widget.entry, meta: widget.meta);
  }
}

class _HistoryPlaceholder extends StatelessWidget {
  const _HistoryPlaceholder({required this.entry, required this.meta});

  final LadybirdSessionHistoryEntry entry;
  final TabHistoryEntryMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favicon = meta?.favicon;
    final title = meta?.title;

    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (favicon is ui.Image)
            RawImage(image: favicon, width: 40, height: 40)
          else
            Icon(
              Icons.public,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          const SizedBox(height: 12),
          if (title != null && title.isNotEmpty)
            Text(
              title,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 4),
          Text(
            entry.url,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
