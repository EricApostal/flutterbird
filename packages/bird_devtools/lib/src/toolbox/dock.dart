import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'manager.dart';
import 'responsive_view.dart';
import 'theme_scope.dart';
import 'toolbox.dart';

/// A tab's toolbox on its own: for a dock, or for a window to itself.
class DevToolsToolboxHost extends StatelessWidget {
  const DevToolsToolboxHost({super.key, required this.manager, required this.tabId, this.autoBrightness});

  final DevToolsManager manager;
  final int tabId;
  final Brightness? autoBrightness;

  @override
  Widget build(BuildContext context) => DevToolsScope(
    settings: manager.settings,
    autoBrightness: autoBrightness,
    child: ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final tab = manager.stateOf(tabId);
        if (tab == null || !tab.toolboxOpen) return const SizedBox.shrink();
        final session = tab.session;
        if (session == null) {
          return ColoredBox(
            color: context.dt.body,
            child: tab.error.isEmpty
                ? const DtEmptyState('Starting the developer tools…')
                : DtEmptyState(
                    'The developer tools could not start.',
                    detail: tab.error,
                    actions: [
                      DtButton('Retry', primary: true, onPressed: () => manager.retry(tabId)),
                      DtButton('Close', onPressed: () => manager.close(tabId)),
                    ],
                  ),
          );
        }
        return DevToolsToolbox(
          key: ObjectKey(session),
          session: session,
          panel: tab.panel,
          onSelectPanel: (panel) => manager.selectPanel(tabId, panel),
          focusNode: tab.focus,
          chrome: ToolboxChrome(
            onClose: () => manager.close(tabId),
            dock: manager.dock,
            onDock: manager.setDock,
            supportsWindow: manager.supportsSeparateWindow,
            responsive: tab.responsive,
            onToggleResponsive: () => manager.toggleResponsive(tabId),
          ),
        );
      },
    ),
  );
}

/// A tab's page with its developer tools docked beside it, when they are open.
class DevToolsDockLayout extends StatefulWidget {
  const DevToolsDockLayout({
    super.key,
    required this.manager,
    required this.tabId,
    required this.page,
    this.hidden = false,
    this.autoBrightness,
  });

  final DevToolsManager manager;
  final int tabId;
  final Widget page;

  /// Shows the page alone, whatever is open, as for a fullscreen video.
  final bool hidden;
  final Brightness? autoBrightness;

  @override
  State<DevToolsDockLayout> createState() => _DevToolsDockLayoutState();
}

class _DevToolsDockLayoutState extends State<DevToolsDockLayout> {
  // The page keeps its state as the tools move around it.
  final GlobalKey _pageKey = GlobalKey(debugLabel: 'inspected page');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.manager,
    builder: (context, _) {
      final manager = widget.manager;
      final tab = manager.stateOf(widget.tabId);
      final page = KeyedSubtree(key: _pageKey, child: widget.page);
      if (tab == null || widget.hidden) return page;
      final framed = !tab.responsive
          ? page
          : DevToolsScope(
              settings: manager.settings,
              autoBrightness: widget.autoBrightness,
              child: ResponsiveView(
                settings: manager.settings,
                onClose: () => manager.toggleResponsive(widget.tabId),
                child: page,
              ),
            );
      final dock = manager.dock;
      if (!tab.toolboxOpen || dock == DevToolsDock.window) return framed;
      final toolbox = DevToolsToolboxHost(
        key: ValueKey(widget.tabId),
        manager: manager,
        tabId: widget.tabId,
        autoBrightness: widget.autoBrightness,
      );
      return DevToolsScope(
        settings: manager.settings,
        autoBrightness: widget.autoBrightness,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottom = dock == DevToolsDock.bottom;
            final before = dock == DevToolsDock.left;
            return DtSplit(
              key: ValueKey(dock),
              axis: bottom ? Axis.vertical : Axis.horizontal,
              initialSize: bottom ? (constraints.maxHeight * 0.42).clamp(200, 440) : (constraints.maxWidth * 0.4).clamp(320, 640),
              sizeSecond: !before,
              minSize: bottom ? 110 : 280,
              minOther: bottom ? 60 : 200,
              settings: manager.settings,
              settingKey: 'dock.${dock.name}.size',
              first: before ? toolbox : framed,
              second: before ? framed : toolbox,
            );
          },
        ),
      );
    },
  );
}
