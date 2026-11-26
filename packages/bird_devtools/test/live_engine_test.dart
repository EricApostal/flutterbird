// Runs the tools against a real engine. Skipped unless an engine is listening:
//
//   python3 -m http.server 8765 --bind 127.0.0.1 --directory test/site
//   Ladybird --headless=manual --temporary-profile --devtools=6789 \
//       http://127.0.0.1:8765/index.html
//   BIRD_DEVTOOLS_PORT=6789 flutter test test/live_engine_test.dart
import 'dart:io';

import 'package:bird_devtools/bird_devtools.dart';
import 'package:bird_devtools/src/model/console_controller.dart';
import 'package:bird_devtools/src/model/dom.dart';
import 'package:bird_devtools/src/model/storage_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

void main() {
  final port = int.tryParse(Platform.environment['BIRD_DEVTOOLS_PORT'] ?? '');
  final address =
      Platform.environment['BIRD_DEVTOOLS_PAGE'] ??
      'http://127.0.0.1:8765/index.html';

  test(
    'every tool works against a running engine',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final clock = Stopwatch()..start();
      void mark(String section) =>
          stdout.writeln('>> ${clock.elapsed.inMilliseconds}ms $section');
      final connection = await DevToolsConnection.open(port!);
      final tabs = await connection.listTabs();
      expect(tabs, isNotEmpty);
      final settings = DevToolsSettings();
      final session = ToolboxSession(
        connection: connection,
        browserId: tabs.first.browserId,
        settings: settings,
      );
      await session.start();
      expect(session.state, SessionState.ready, reason: session.failure);
      await connection.request(tabs.first.actor, 'navigateTo', {'url': address});
      await Future<void>.delayed(const Duration(seconds: 2));

      mark('Console:');
      // Console: what the page logged while loading.
      final console = session.console;
      await until(
        () => console.entries.any((e) => e.plainText.contains('loaded 42')),
        'the load log',
      );
      await until(
        () => console.entries.any((e) => e.kind == ConsoleEntryKind.pageError),
        'the async error',
      );
      expect(console.entries.any((e) => e.level == 'table'), isTrue);
      expect(console.entries.any((e) => e.stack.isNotEmpty), isTrue);
      await console.execute('6 * 7');
      expect(console.entries.last.arguments.single.describe(), '42');
      await console.execute('({a: [1, 2], b: "x"})');
      expect(console.entries.last.arguments.single.isExpandable, isTrue);
      final completion = await console.complete('document.bo', 11);
      expect(completion?.matches, contains('body'));
      await console.execute(r'$0.tagName');
      expect(console.entries.last.arguments.single.describe(), 'BODY');
      expect(await session.runInPage('return [1, 2, 3];'), [1, 2, 3]);

      mark('Network:');
      // Network: the page's own load, with details.
      final network = session.network;
      session.reload(bypassCache: true);
      // Subresources may come from memory, which sends no events: the
      // engine ignores the request to bypass its caches.
      await until(
        () => network.requests.any((r) => r.isNavigation && r.status == 200),
        'the requests of a load',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await console.execute('fetch("app.js", {cache: "no-store"}); 1');
      await until(
        () => network.requests.any((r) => r.isXhr && r.complete),
        'a fetch',
      );
      final script = network.requests.lastWhere((r) => r.isXhr);
      expect(script.status, 200);
      await network.loadDetails(script, content: true);
      expect(script.requestHeaders, isNotEmpty, reason: script.detailsError);
      expect(script.responseHeaders, isNotEmpty);
      expect(script.content?.asText, contains('function go()'));
      expect(script.timings, isNotNull);
      expect(script.asCurl, startsWith("curl 'http"));
      await until(() => network.loadMs != null, 'load timing');
      expect(network.exportHar(), contains('app.js'));

      mark('Inspector:');
      // Inspector: the tree, selection and the sidebar.
      final inspector = session.inspector;
      await until(() => inspector.selected != null, 'a selected node');
      await until(() => inspector.computed.isNotEmpty, 'computed style');
      DomNode find(String Function(DomNode) read, String value) {
        DomNode? found;
        void visit(DomNode node) {
          if (read(node) == value) found ??= node;
          node.children?.forEach(visit);
        }

        visit(inspector.root!);
        return found!;
      }

      final main = find((n) => n.isElement ? n.id : '', 'main');
      expect(main.cssSelector, '#main');
      expect(main.xpath, '//*[@id="main"]');
      inspector.select(main);
      await until(
        () => inspector.flexContainer != null && inspector.rules.length > 1,
        'flexbox and rules',
      );
      expect(inspector.flexContainer!.items, hasLength(2));
      expect(inspector.grids, hasLength(1));
      expect(inspector.boxModel['padding-left'], '12px');
      inspector.highlight(main);
      inspector.toggleGridHighlighter(inspector.grids.single.nodeActor, true);

      mark('Editing a style');
      // Editing a style sheet rule goes through the page.
      var rule = inspector.rules.firstWhere((r) => r.selectorText == '#main');
      final gap = rule.declarations.firstWhere((d) => d.name == 'gap');
      await inspector.editDeclaration(rule, gap, value: '20px');
      expect(inspector.ruleError, isEmpty);
      expect(
        await session.runInPage(
          'return getComputedStyle(document.querySelector("#main")).columnGap;',
        ),
        '20px',
      );
      rule = inspector.rules.firstWhere((r) => r.selectorText == '#main');
      final padding = rule.declarations.firstWhere((d) => d.name == 'padding');
      await inspector.setDeclarationEnabled(rule, padding, false);
      rule = inspector.rules.firstWhere((r) => r.selectorText == '#main');
      expect(rule.declarations.any((d) => !d.enabled), isTrue);
      await inspector.setDeclarationEnabled(
        rule,
        rule.declarations.firstWhere((d) => !d.enabled),
        true,
      );
      expect(inspector.changes, isNotEmpty);

      mark('The elements own');
      // The element's own style.
      rule = inspector.rules.firstWhere((r) => r.isElementStyle);
      await inspector.addDeclaration(rule, 'opacity', '0.5');
      await until(
        () => main.attribute('style')?.contains('opacity') ?? false,
        'the style attribute',
      );

      mark('DOM edits');
      // DOM edits arrive back as mutations.
      await inspector.setAttribute(main, 'data-probe', 'yes');
      await until(() => main.attribute('data-probe') == 'yes', 'attribute');
      await inspector.replaceAttribute(main, 'data-probe', 'data-other="1"');
      await until(() => main.attribute('data-other') == '1', 'replacement');
      await inspector.removeAttribute(main, 'data-other');
      await until(() => main.attribute('data-other') == null, 'removal');
      final before = main.childCount;
      await inspector.addChild(main);
      await until(() => main.childCount == before + 1, 'a new child');
      await inspector.removeNode(main.children!.last);
      await until(() => main.childCount == before, 'the child to go');
      expect(await inspector.html(main), startsWith('<div id="main"'));

      mark('Search by');
      // Search by selector and by text.
      await inspector.runSearch('.grid > div');
      expect(inspector.search!.matches.length, greaterThanOrEqualTo(2));
      await inspector.runSearch('Hello DevTools');
      expect(inspector.search!.matches, isNotEmpty);
      expect(inspector.selected!.tag, 'h1');

      mark('Forcing');
      // Forcing a state.
      await inspector.setPseudoClassLock(inspector.selectedElement!, 'hover', true);
      expect(inspector.ruleError, isEmpty);
      await inspector.setPseudoClassLock(inspector.selectedElement!, 'hover', false);

      mark('A console value');
      // A console value leads back to its node.
      await console.execute('document.querySelector("#btn")');
      final reference = console.entries.last.arguments.single.contentDomReference!;
      await inspector.selectContentDomReference(reference);
      expect(inspector.selected!.id, 'btn');

      mark('Debugger:');
      // Debugger: sources, a breakpoint, scopes, stepping, watches.
      final debugger = session.debugger;
      await until(() => debugger.sources.isNotEmpty, 'sources');
      final source = debugger.sources.firstWhere((s) => s.fileName == 'app.js');
      final text = await debugger.loadSource(source);
      expect(text.text, contains('function go()'));
      debugger.addWatch('1 + 2');
      await debugger.addBreakpoint(source.url, 3);
      expect(debugger.error, isEmpty);
      final run = console.execute('go().a');
      await until(() => debugger.isPaused, 'the breakpoint');
      expect(debugger.pause!.reason, 'breakpoint');
      expect(debugger.selectedFrame!.line, 3);
      await until(() => debugger.pause?.scopes != null, 'scopes');
      expect(
        debugger.pause!.scopes!.first.bindings.map((b) => b.name),
        contains('data'),
      );
      await until(() => debugger.pause!.frames.length > 1, 'the stack');
      await debugger.stepOver();
      await until(() => debugger.pause?.frames.first.line == 4, 'a step');
      await debugger.resume();
      await run;
      expect(console.entries.last.arguments.single.describe(), '1');
      await debugger.removeAllBreakpoints();
      await until(
        () => debugger.watchValues.firstOrNull?.value.describe() == '3',
        'the watch',
      );

      mark('Style editor');
      // Style editor: read, edit live, disable.
      final styles = session.styleEditor;
      await until(() => styles.sheets.length >= 2, 'style sheets');
      final linked = styles.sheets.firstWhere((s) => s.href.isNotEmpty);
      await styles.load(linked);
      expect(linked.text, contains('h1'), reason: linked.error);
      styles.edit(linked, 'h1 { color: rgb(1, 2, 3) !important; }');
      await styles.apply(linked);
      expect(linked.error, isEmpty);
      expect(
        await session.runInPage(
          'return getComputedStyle(document.querySelector("h1")).color;',
        ),
        'rgb(1, 2, 3)',
      );
      await styles.setDisabled(linked, true);
      expect(linked.error, isEmpty);

      mark('Storage.');
      // Storage.
      final storage = session.storage;
      await until(() => storage.roots.length == 4, 'storage roots');
      final host = storage.roots[StorageKind.localStorage]!.hosts.keys.first;
      storage.select(StorageSelection(StorageKind.localStorage, host));
      await until(() => storage.rows.any((r) => r['name'] == 'lk'), 'storage');
      await storage.editCell(
        storage.rows.firstWhere((r) => r['name'] == 'lk'),
        'value',
        'changed',
      );
      await until(() => storage.rows.any((r) => r['value'] == 'changed'), 'edit');
      await storage.addItem();
      await until(() => storage.rows.length >= 2, 'a new item');
      await storage.removeRow(
        storage.rows.firstWhere((r) => r['name'] != 'lk'),
      );
      expect(storage.error, isEmpty);
      storage.select(StorageSelection(StorageKind.cookies, host));
      await until(() => storage.rows.any((r) => r['name'] == 'ck'), 'cookies');
      await storage.editCell(
        storage.rows.firstWhere((r) => r['name'] == 'ck'),
        'value',
        'baked',
      );
      await until(() => storage.rows.any((r) => r['value'] == 'baked'), 'cookie');

      mark('Accessibility.');
      // Accessibility.
      final accessibility = session.accessibility;
      await accessibility.refresh();
      expect(accessibility.root, isNotNull, reason: accessibility.error);
      expect(accessibility.visibleNodes.length, greaterThan(2));
      await accessibility.select(accessibility.visibleNodes[1]);
      expect(accessibility.properties, isNotEmpty);
      await accessibility.checkForIssues();
      expect(accessibility.issues, isNotNull);

      mark('Performance and');
      // Performance and application.
      await session.performance.start();
      await Future<void>.delayed(const Duration(seconds: 1));
      await session.performance.stop();
      expect(session.performance.result, isNotNull,
          reason: session.performance.error);
      stdout.writeln(
        'performance: ${session.performance.result!.frames.length} frames',
      );
      await session.application.refresh();
      expect(session.application.loaded, isTrue);

      mark('A reload');
      // A reload brings everything back, with the same element selected.
      inspector.select(find((n) => n.isElement ? n.id : '', 'btn'));
      final targetBefore = session.target!.actor;
      session.reload();
      await until(
        () => session.target != null && session.target!.actor != targetBefore,
        'the new target',
      );
      await until(
        () => inspector.selected?.id == 'btn',
        'the selection after reload',
      );
      await until(() => debugger.sources.isNotEmpty, 'sources after reload');
      await until(() => styles.sheets.length >= 2, 'sheets after reload');
      styles.select(styles.sheets.first);
      await styles.load(styles.sheets.first);
      expect(styles.sheets.first.text, contains(':root'), reason: styles.sheets.first.error);

      session.dispose();
      await connection.close();
    },
    skip: port == null ? 'No engine: set BIRD_DEVTOOLS_PORT' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
