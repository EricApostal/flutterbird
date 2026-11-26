// Renders the toolbox, attached to a running engine, into PNG files, to look
// the tools over without building a browser. Skipped unless asked for:
//
//   BIRD_DEVTOOLS_SHOTS=/some/dir tool/live_test.sh test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bird_devtools/bird_devtools.dart';
import 'package:bird_devtools/src/model/dom.dart';
import 'package:bird_devtools/src/model/object_tree.dart';
import 'package:bird_devtools/src/model/storage_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void main() {
  final port = int.tryParse(Platform.environment['BIRD_DEVTOOLS_PORT'] ?? '');
  final directory = Platform.environment['BIRD_DEVTOOLS_SHOTS'];
  final only = Platform.environment['BIRD_DEVTOOLS_ONLY'];

  testWidgets(
    'screenshots',
    (tester) async {
      final boundary = GlobalKey();
      final settings = DevToolsSettings()..load({'theme': 'light'});
      late DevToolsConnection connection;
      late ToolboxSession session;
      var panel = 'inspector';
      void Function(void Function())? rebuild;

      // Sockets live in real time and widgets in the test's: both are driven.
      Future<void> pump([int milliseconds = 600]) async {
        for (var waited = 0; waited < milliseconds; waited += 30) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      Future<void> until(bool Function() ready, String what) async {
        for (var i = 0; i < 200; i++) {
          if (ready()) return;
          await pump(60);
        }
        fail('Timed out waiting for $what');
      }

      Future<T> settle<T>(Future<T> future, [int timeout = 10000]) async {
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
        for (var waited = 0; !done && waited < timeout; waited += 60) {
          await pump(60);
        }
        if (failure != null) throw failure!;
        if (!done) fail('A future did not finish');
        return result as T;
      }

      Future<void> shot(String name) async {
        await pump(400);
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$directory/$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> size(double width, double height) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = Size(width * 2, height * 2);
        await pump(200);
      }

      await tester.runAsync(() async {
        await _loadFont('.AppleSystemUIFont', '/System/Library/Fonts/SFNS.ttf');
        await _loadFont('Menlo', '/System/Library/Fonts/Menlo.ttc');
      });
      await tester.runAsync(() async {
        connection = await DevToolsConnection.open(port!);
        final tabs = await connection.listTabs();
        session = ToolboxSession(connection: connection, browserId: tabs.first.browserId, settings: settings);
        await session.start();
      });
      session.onSelectTool = (next) => rebuild?.call(() => panel = next);

      await size(1200, 640);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery.fromView(
              view: tester.view,
              child: DevToolsScope(
                settings: settings,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return DevToolsToolbox(
                      session: session,
                      panel: panel,
                      onSelectPanel: (next) => setState(() => panel = next),
                      chrome: ToolboxChrome(onClose: () {}, dock: DevToolsDock.bottom, onDock: (_) {}, onToggleResponsive: () {}),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => connection.request('root', 'listTabs'));
      session.reload();
      await pump(2500);

      bool wanted(String name) => only == null || only.split(',').contains(name);
      Future<void> show(String name) async {
        rebuild!(() => panel = name);
        await pump(700);
      }

      DomNode? find(String id) {
        DomNode? found;
        void visit(DomNode node) {
          if (node.isElement && node.id == id) found ??= node;
          node.children?.forEach(visit);
        }

        if (session.inspector.root case final root?) visit(root);
        return found;
      }

      await until(() => find('main') != null, 'the tree');
      final main = find('main')!;
      await settle(session.inspector.expand(main));
      session.inspector.select(main);
      await until(() => session.inspector.rules.length > 1, 'rules');
      if (wanted('inspector')) {
        await shot('01-inspector');
        settings.set('inspector.sidebarTab', 'layout');
        await show('inspector');
        await shot('02-inspector-layout');
        settings.set('inspector.sidebarTab', 'computed');
        await shot('03-inspector-computed');
        settings
          ..set('inspector.sidebarTab', 'layout')
          ..set('inspector.threePane', true);
        await shot('04-inspector-3pane');
        settings
          ..set('inspector.threePane', false)
          ..set('inspector.sidebarTab', 'rules');
      }

      if (wanted('console')) {
        await show('console');
        await settle(session.console.execute('settings'));
        await settle(session.console.execute('document.querySelector("#main")'));
        await settle(session.console.execute('[1, "two", {three: 3}, null]'));
        await settle(session.console.execute('go()'));
        final result = session.console.entries.firstWhere((e) => e.plainText.contains('theme'));
        session.console.objects.toggle('${result.id}:0', ObjectEntry('', value: result.arguments.first));
        await pump(900);
        await shot('05-console');
        session.console.draft = 'document.qu';
        settings.splitConsole = true;
        await show('inspector');
        await shot('06-split-console');
        settings.splitConsole = false;
        session.console.draft = '';
      }

      if (wanted('debugger')) {
        await show('debugger');
        await until(() => session.debugger.sources.any((s) => s.fileName == 'app.js'), 'sources');
        final source = session.debugger.sources.firstWhere((s) => s.fileName == 'app.js');
        session.debugger.openSource(source.url);
        await pump(900);
        session.debugger.addWatch('window.settings.retries * 2');
        await settle(session.debugger.addBreakpoint(source.url, 3));
        final run = session.console.execute('go().a');
        await until(() => session.debugger.pause?.scopes != null, 'a pause');
        await pump(1500);
        await shot('07-debugger-paused');
        await settle(session.debugger.resume());
        await settle(run);
        await settle(session.debugger.removeAllBreakpoints());
        // The page's inline script, to see what the engine gives as its text.
        final inline = session.debugger.sources.where((s) => s.url.endsWith('index.html')).firstOrNull;
        if (inline != null) {
          session.debugger.openSource(inline.url);
          await pump(900);
          await shot('08-debugger-inline');
        }
      }

      if (wanted('network')) {
        await show('network');
        session.reload();
        await pump(2000);
        await settle(session.console.execute('fetch("style.css?v=2", {cache: "no-store"}); fetch("missing.json"); 1'));
        await pump(1500);
        await shot('09-network');
        final request = session.network.requests.lastWhere((r) => r.url.contains('style.css'));
        session.network.select(request);
        await pump(900);
        await shot('10-network-headers');
        session.network.detailTab = 'response';
        session.network.changed();
        await pump(900);
        await shot('11-network-response');
        session.network.select(null);
      }

      if (wanted('styles')) {
        await show('styleeditor');
        await until(() => session.styleEditor.selected?.text != null, 'a style sheet');
        await shot('12-style-editor');
      }

      if (wanted('storage')) {
        await show('storage');
        await until(() => session.storage.roots.length == 4, 'storage');
        final host = session.storage.roots[StorageKind.cookies]!.hosts.keys.first;
        session.storage.select(StorageSelection(StorageKind.cookies, host));
        await until(() => session.storage.rows.isNotEmpty, 'cookies');
        session.storage.selectRow(session.storage.rows.first);
        await shot('13-storage');
      }

      if (wanted('misc')) {
        await show('accessibility');
        await until(() => session.accessibility.root != null, 'accessibility');
        await pump(900);
        session.accessibility.select(session.accessibility.visibleNodes[1]);
        await shot('14-accessibility');
        await show('performance');
        await settle(session.performance.start());
        await pump(900);
        await settle(session.performance.stop());
        await shot('15-performance');
        await show('settings');
        await shot('16-settings');
      }

      if (wanted('dark')) {
        settings.theme = DevToolsThemeChoice.dark;
        await show('inspector');
        await shot('17-dark-inspector');
        await show('console');
        await shot('18-dark-console');
        await show('network');
        await shot('19-dark-network');
        await show('debugger');
        await shot('20-dark-debugger');
      }

      if (wanted('narrow')) {
        await size(420, 760);
        await show('inspector');
        await shot('21-docked-side-inspector');
        await show('console');
        await shot('22-docked-side-console');
        await size(1200, 640);
      }

      await tester.runAsync(() async {
        session.dispose();
        await connection.close();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 40));
    },
    skip: port == null || directory == null,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
