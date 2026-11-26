import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

/// Implemented by the Android app's activity.
const MethodChannel _platform = MethodChannel('rubisco/platform');

/// Hands [text] to the system's share sheet. Where there is none, it is copied.
Future<void> shareText(
  BuildContext context,
  String text, {
  String? subject,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await _platform.invokeMethod<void>('shareText', {
      'text': text,
      'subject': ?subject,
    });
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text));
    showMobileSnack(messenger, 'Link copied');
  } on PlatformException catch (error) {
    debugPrint('Could not share: $error');
    await Clipboard.setData(ClipboardData(text: text));
    showMobileSnack(messenger, 'Link copied');
  }
}

Future<void> copyText(
  BuildContext context,
  String text, {
  String message = 'Link copied',
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  showMobileSnack(messenger, message);
}

/// Goes to [url] in the tab being used, closing whatever is over it.
void openInCurrentTab(BuildContext context, String url) {
  // What is needed from the context is taken first: closing the screens over
  // the browser takes it with them.
  final shell = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(browserShellProvider);
  final windowId = BrowserWindowScope.of(context);
  closeMobileOverlays(Navigator.of(context, rootNavigator: true));

  final tabId = shell.session.window(windowId)?.activeTabId;
  final tab = tabId == null ? null : shell.controllerFor(tabId);
  if (tab == null) {
    shell.openTab(windowId: windowId, url: url);
    return;
  }
  tab.navigate(url);
  // Also what leaves the tab switcher, if that is what was underneath.
  shell.showTab(tab.viewId);
}

/// Opens [url] in a new tab and goes to it, closing whatever is over the
/// browser.
void openInNewTab(BuildContext context, String url) {
  final shell = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(browserShellProvider);
  final windowId = BrowserWindowScope.of(context);
  closeMobileOverlays(Navigator.of(context, rootNavigator: true));
  shell.openTab(windowId: windowId, url: url);
}

/// Opens [url] in a tab of its own behind what is on screen, and says so, with
/// a way to go there.
void openInBackgroundTab(BuildContext context, String url) {
  final shell = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(browserShellProvider);
  final tab = shell.openTab(
    windowId: BrowserWindowScope.of(context),
    url: url,
    activate: false,
  );
  showMobileSnack(
    ScaffoldMessenger.maybeOf(context),
    'Opened in new tab',
    action: 'Switch',
    onAction: () => shell.showTab(tab.viewId),
  );
}

/// Whether an address is of a page worth sharing, bookmarking or showing.
bool isShareableUrl(String url) =>
    url.isNotEmpty && url != 'about:newtab' && url != 'about:blank';
