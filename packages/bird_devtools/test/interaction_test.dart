// Drives the tools with clicks and keys, the way the browser hosts them,
// against a running engine. Skipped unless one is listening:
//
//   tool/live_test.sh test/interaction_test.dart
import 'dart:async';
import 'dart:io';

import 'package:bird_devtools/bird_devtools.dart';
import 'package:bird_devtools/src/model/console_controller.dart';
import 'package:bird_devtools/src/model/network_controller.dart';
import 'package:bird_devtools/src/panels/network_panel.dart';
import 'package:bird_devtools/src/toolbox/responsive_view.dart';
import 'package:bird_devtools/src/ui/code_view.dart';
import 'package:bird_devtools/src/ui/icons.dart';
import 'package:bird_devtools/src/ui/inline_editor.dart';
import 'package:bird_devtools/src/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host implements DevToolsHost {
  _Host(this.port, this.browserId);
  final int port;
  final int browserId;
  int starts = 0;
  int stops = 0;
  final List<String> opened = [];

  @override
  Future<int> startServer() async {
    starts++;
    return port;
  }

  @override
  void stopServer() => stops++;

  @override
  int? browserIdFor(int tabId) => browserId;

  @override
  void openLink(String url, {required int fromTab}) => opened.add(url);

  @override
  Future<String?> saveFile(String suggestedName, List<int> bytes) async => null;
}

/// Stands for the web view, and counts how often it is made anew.
class _Page extends StatefulWidget {
  const _Page();

  static int created = 0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _Page.created++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFFFFFFF), child: SizedBox.expand());
}

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

void main() {
  final port = int.tryParse(Platform.environment['BIRD_DEVTOOLS_PORT'] ?? '');

  testWidgets(
    'the tools answer to the mouse and keyboard',
    (tester) async {
      Future<void> pump([int milliseconds = 450]) async {
        for (var waited = 0; waited < milliseconds; waited += 30) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      Future<void> until(bool Function() ready, String what) async {
        for (var i = 0; i < 150; i++) {
          if (ready()) return;
          await pump(60);
        }
        fail('Timed out waiting for $what');
      }

      Future<T> settle<T>(Future<T> future) async {
        T? result;
        Object? failure;
        var done = false;
        future.then((value) {
          result = value;
          done = true;
        }, onError: (Object error) {
          failure = error;
          done = true;
        });
        await until(() => done, 'a future');
        if (failure != null) throw failure!;
        return result as T;
      }

      // Rich text is what most of the tools draw with.
      Finder rich(String text) => find.textContaining(text, findRichText: true).hitTestable();
      Finder exact(String text) => find.text(text, findRichText: true).hitTestable();

      Future<void> click(Finder finder, {int buttons = kPrimaryButton}) async {
        expect(finder, findsWidgets, reason: 'nothing to click: $finder');
        await tester.tap(finder.first, buttons: buttons, kind: PointerDeviceKind.mouse);
        await pump(150);
      }

      Future<void> doubleClick(Finder finder) async {
        expect(finder, findsWidgets, reason: 'nothing to double click: $finder');
        final at = tester.getCenter(finder.first);
        for (var i = 0; i < 2; i++) {
          final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await gesture.down(at, timeStamp: Duration(milliseconds: 1000 + i * 120));
          await gesture.up(timeStamp: Duration(milliseconds: 1040 + i * 120));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await pump(200);
      }

      Future<void> key(LogicalKeyboardKey logical) async {
        await tester.sendKeyEvent(logical);
        await pump(300);
      }

      await tester.runAsync(() async {
        await _loadFont('.AppleSystemUIFont', '/System/Library/Fonts/SFNS.ttf');
        await _loadFont('Menlo', '/System/Library/Fonts/Menlo.ttc');
      });
      late int browserId;
      await tester.runAsync(() async {
        final probe = await DevToolsConnection.open(port!);
        browserId = (await probe.listTabs()).first.browserId;
        await probe.close();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final host = _Host(port!, browserId);
      // Connected in real time, where the socket's events are delivered.
      late Zone realZone;
      await tester.runAsync(() async => realZone = Zone.current);
      final manager = DevToolsManager(host, connect: (port) => realZone.run(() => DevToolsConnection.open(port)));
      manager.settings.load({'theme': 'light', 'dock': 'bottom', 'dock.bottom.size': 520.0});

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery.fromView(
            view: tester.view,
            child: DevToolsDockLayout(manager: manager, tabId: 7, page: const _Page()),
          ),
        ),
      );
      expect(find.byType(DevToolsToolbox), findsNothing);

      // ---------------------------------------------------------- opening
      manager.toggle(7);
      await until(() => manager.stateOf(7)?.session?.isReady ?? false, 'the session');
      final session = manager.stateOf(7)!.session!;
      expect(host.starts, 1);
      await settle(session.connection.request('root', 'listTabs'));
      session.reload();
      await until(() => session.inspector.selected?.tag == 'body', 'the page body');
      await pump(900);
      expect(find.byType(DevToolsToolbox), findsOneWidget);
      expect(_Page.created, 1, reason: 'docking the tools must keep the page');

      // ---------------------------------------------------------- inspector
      await click(rich('id="btn"'));
      expect(session.inspector.selected!.id, 'btn');
      await until(() => session.inspector.computed.isNotEmpty, 'computed');

      // Arrow keys walk the tree.
      await key(LogicalKeyboardKey.arrowUp);
      expect(session.inspector.selected!.classes, contains('grid'));
      await key(LogicalKeyboardKey.arrowRight);
      await until(() => session.inspector.expanded.contains(session.inspector.selected!.actor), 'expanding');
      await key(LogicalKeyboardKey.arrowLeft);
      expect(session.inspector.expanded.contains(session.inspector.selected!.actor), isFalse);

      // Editing an attribute in place.
      await doubleClick(rich('id="btn"'));
      expect(find.byType(DtInlineEditor), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(DtInlineEditor), matching: find.byType(EditableText)), 'id="renamed" title="hi"');
      await key(LogicalKeyboardKey.enter);
      await until(() => session.inspector.selected?.attribute('title') == 'hi', 'the new attributes');
      expect(session.inspector.selected!.id, 'renamed');
      expect(find.byType(DtInlineEditor), findsNothing);

      // The context menu.
      await click(rich('id="renamed"'), buttons: kSecondaryButton);
      expect(exact('Delete Node'), findsOneWidget);
      await click(exact('Duplicate Node'));
      await until(() => session.inspector.selected?.parent?.children?.where((n) => n.tag == 'button').length == 2, 'a duplicate');
      await click(rich('id="renamed"'), buttons: kSecondaryButton);
      await key(LogicalKeyboardKey.escape);
      expect(exact('Delete Node'), findsNothing);
      await click(rich('id="renamed"'));
      await key(LogicalKeyboardKey.delete);
      await until(() => session.inspector.selected?.parent?.children?.where((n) => n.tag == 'button').length == 1, 'the deletion');

      // Editing a style in the rules view reaches the page.
      await click(rich('id="main"'));
      await until(() => session.inspector.rules.any((r) => r.selectorText == '#main'), 'rules');
      await pump(600);
      await click(exact('8px'));
      expect(find.byType(DtInlineEditor), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(DtInlineEditor), matching: find.byType(EditableText)), '30px');
      await key(LogicalKeyboardKey.enter);
      await pump(900);
      expect(await settle(session.runInPage('return getComputedStyle(document.querySelector("#main")).columnGap;')), '30px');

      // Adding a declaration: click the closing brace, name, then value.
      await click(exact('element {'));
      await tester.enterText(find.descendant(of: find.byType(DtInlineEditor), matching: find.byType(EditableText)), 'opaci');
      await pump(300);
      await key(LogicalKeyboardKey.tab);
      await pump(300);
      expect(find.byType(DtInlineEditor), findsOneWidget, reason: 'the value field follows the name');
      await tester.enterText(find.descendant(of: find.byType(DtInlineEditor), matching: find.byType(EditableText)), '0.4');
      await key(LogicalKeyboardKey.enter);
      await pump(900);
      expect(await settle(session.runInPage('return document.querySelector("#main").style.opacity;')), '0.4');

      // Sidebar tabs.
      await click(exact('Layout'));
      expect(exact('Box Model'), findsOneWidget);
      await click(exact('Computed'));
      expect(rich('Browser Styles'), findsWidgets);
      await click(exact('Rules'));

      // The picker button.
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.picker));
      expect(session.inspector.picking, isTrue);
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.picker));
      expect(session.inspector.picking, isFalse);

      // ---------------------------------------------------------- split console
      await key(LogicalKeyboardKey.escape);
      expect(manager.settings.splitConsole, isTrue);
      expect(find.textContaining('Filter Output', findRichText: true), findsWidgets);
      await key(LogicalKeyboardKey.escape);
      expect(manager.settings.splitConsole, isFalse);

      // ---------------------------------------------------------- console
      await click(exact('Console'));
      expect(manager.stateOf(7)!.panel, 'console');
      await click(find.byWidgetPredicate((w) => w is DtIcon && w.glyph == DtGlyph.trash).hitTestable());
      expect(session.console.entries, isEmpty);
      final prompt = find.byType(EditableText).hitTestable().last;
      await tester.tap(prompt);
      await pump(150);
      await tester.enterText(prompt, 'document.bo');
      await until(() => find.byType(DtCompletionPopup).evaluate().isNotEmpty, 'completions');
      await key(LogicalKeyboardKey.tab);
      expect(tester.widget<EditableText>(prompt).controller.text, 'document.body');
      await key(LogicalKeyboardKey.enter);
      await until(() => session.console.entries.length >= 2, 'the result');
      expect(session.console.entries.last.arguments.single.className, 'HTMLBodyElement');
      expect(tester.widget<EditableText>(prompt).controller.text, isEmpty);
      // History comes back with the up arrow.
      await key(LogicalKeyboardKey.arrowUp);
      expect(tester.widget<EditableText>(prompt).controller.text, 'document.body');
      await tester.enterText(prompt, '({alpha: {beta: 1}})');
      await pump(300);
      await key(LogicalKeyboardKey.escape);
      await key(LogicalKeyboardKey.enter);
      await until(() => session.console.entries.length >= 4, 'an object');
      await click(rich('Object { alpha: Object'));
      await pump(900);
      expect(rich('<prototype>'), findsWidgets);
      // Filtering the output.
      session.console.filterText = 'nothing like this';
      await pump(200);
      expect(session.console.visibleEntries.where((e) => e.category != ConsoleCategory.always), isEmpty);
      session.console.filterText = '';

      // ---------------------------------------------------------- debugger
      await click(exact('Debugger'));
      await until(() => session.debugger.sources.isNotEmpty, 'sources');
      await pump(300);
      await click(exact('app.js'));
      await until(() => find.byType(DtCodeView).evaluate().isNotEmpty, 'the source');
      await pump(900);
      await click(exact('3'));
      expect(session.debugger.breakpoints.single.line, 3);
      final run = session.console.execute('go().a');
      await until(() => session.debugger.pause?.scopes != null, 'a pause');
      await pump(600);
      expect(exact('Paused on breakpoint'), findsOneWidget);
      await key(LogicalKeyboardKey.f10);
      await until(() => session.debugger.pause?.frames.first.line == 4, 'step over');
      await pump(300);
      await key(LogicalKeyboardKey.f8);
      await settle(run);
      await until(() => !session.debugger.isPaused, 'running');
      await pump(300);
      await click(exact('3').first);
      await until(() => session.debugger.breakpoints.isEmpty, 'no breakpoint');
      // Pretty printing and back.
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.prettyPrint));
      expect(session.debugger.prettyPrinted, isNotEmpty);
      await pump(600);
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.prettyPrint));

      // ---------------------------------------------------------- a pause brings the debugger forward
      await click(exact('Inspector'));
      final stop = session.console.execute('(() => { debugger; return 1; })()');
      await until(() => manager.stateOf(7)!.panel == 'debugger', 'the debugger to come forward');
      await until(() => session.debugger.isPaused, 'paused');
      await settle(session.debugger.resume());
      await settle(stop);

      // ---------------------------------------------------------- network
      await click(exact('Network'));
      await settle(session.console.execute('fetch("style.css?probe=1", {cache: "no-store"}); 1'));
      await until(() => session.network.requests.any((r) => r.url.contains('probe=1') && r.complete), 'a request');
      await pump(400);
      await click(rich('style.css?probe=1'));
      expect(find.byType(RequestDetails), findsOneWidget);
      await until(() => session.network.selected?.responseHeaders != null, 'headers');
      await click(exact('Response'));
      await until(() => session.network.selected?.content != null, 'content');
      await click(exact('Timings'));
      await pump(300);
      await click(exact('CSS'));
      expect(session.network.visibleRequests.every((r) => r.category == NetworkCategory.xhr || r.category == NetworkCategory.css), isTrue);
      await click(exact('All'));

      // ---------------------------------------------------------- the other tools open
      for (final tool in ['Style Editor', 'Performance', 'Memory', 'Storage', 'Accessibility', 'Application']) {
        await click(exact(tool));
        await pump(900);
      }
      await click(exact('Local Storage').evaluate().isEmpty ? exact('Application') : exact('Storage'));
      await pump(600);

      // ---------------------------------------------------------- settings and docking
      await click(exact('Inspector'));
      await key(LogicalKeyboardKey.f1);
      expect(exact('Default Developer Tools'), findsOneWidget);
      await click(exact('Dark'));
      expect(manager.settings.theme, DevToolsThemeChoice.dark);
      await key(LogicalKeyboardKey.f1);
      expect(manager.stateOf(7)!.panel, 'inspector');

      Future<void> menu(String item) async {
        await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.meatball));
        await click(exact(item));
        await pump(600);
      }

      await menu('Dock to Right');
      expect(manager.dock, DevToolsDock.right);
      expect(find.byType(DevToolsToolbox), findsOneWidget);
      await menu('Dock to Left');
      await menu('Dock to Bottom');
      expect(_Page.created, 1, reason: 'moving the tools must keep the page');
      expect(manager.stateOf(7)!.session, same(session));

      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.responsive));
      expect(find.byType(ResponsiveView), findsOneWidget);
      expect(tester.getSize(find.byType(_Page)).width, lessThan(500));
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.glyph == DtGlyph.responsive));
      expect(find.byType(ResponsiveView), findsNothing);
      expect(_Page.created, 1);

      // ---------------------------------------------------------- closing while paused
      await settle(session.debugger.addBreakpoint(session.debugger.sources.firstWhere((s) => s.fileName == 'app.js').url, 3));
      session.console.execute('window.finished = false; go(); window.finished = true').ignore();
      await until(() => session.debugger.isPaused, 'paused before closing');
      await click(find.byWidgetPredicate((w) => w is DtIconButton && w.tooltip == 'Close Developer Tools'));
      await until(() => host.stops == 1, 'the server to be stopped');
      expect(find.byType(DevToolsToolbox), findsNothing);
      expect(_Page.created, 1);

      // ---------------------------------------------------------- opening again
      manager.toggle(7);
      await until(() => manager.stateOf(7)?.session?.isReady ?? false, 'a new session');
      final again = manager.stateOf(7)!.session!;
      expect(host.starts, 2);
      await until(() => again.inspector.root != null, 'the tree again');
      // The page was let go: it ran on, past the breakpoint left behind.
      expect(await settle(again.runInPage('return window.finished;')), isTrue);
      expect(again.debugger.isPaused, isFalse);
      await settle(again.debugger.removeAllBreakpoints());

      manager.tabClosed(7);
      await until(() => host.stops == 2, 'the server to stop again');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 40));
    },
    skip: port == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
