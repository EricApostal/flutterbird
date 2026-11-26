import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [builder] as a window's page, and hands back its context.
Future<BuildContext> pumpApp(WidgetTester tester, WidgetBuilder builder) async {
  late BuildContext page;
  await tester.pumpWidget(
    BirdApp(
      themeMode: BirdThemeMode.light,
      home: Builder(
        builder: (context) {
          page = context;
          return Align(alignment: Alignment.topLeft, child: builder(context));
        },
      ),
    ),
  );
  await tester.pump();
  return page;
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey logical) async {
  await tester.sendKeyEvent(logical);
  await tester.pumpAndSettle();
}

void main() {
  group('dialogs', () {
    testWidgets('Escape answers no', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdConfirm(page, title: 'Close all tabs?');
      await tester.pumpAndSettle();
      expect(find.text('Close all tabs?'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(await answer, isFalse);
      expect(find.text('Close all tabs?'), findsNothing);
    });

    testWidgets('Return goes ahead with what is safe', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdConfirm(page, title: 'Open it?', confirmLabel: 'Open');
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.enter);
      expect(await answer, isTrue);
    });

    testWidgets('Return does not destroy anything', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdConfirm(page, title: 'Delete?', confirmLabel: 'Delete', destructive: true);
      await tester.pumpAndSettle();
      // The keyboard starts on Cancel, so Return cancels.
      await key(tester, LogicalKeyboardKey.enter);
      expect(await answer, isFalse);
    });

    testWidgets('Tab moves to a button, and Return presses that one', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdConfirm(page, title: 'Open it?', confirmLabel: 'Open');
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.tab);
      await key(tester, LogicalKeyboardKey.enter);
      expect(await answer, isFalse, reason: 'Cancel comes first, so Tab lands on it');
    });

    testWidgets('a press outside leaves a question open', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      showBirdConfirm(page, title: 'Still here?').ignore();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Still here?'), findsOneWidget);
    });

    testWidgets('a prompt starts with its text selected, and answers with it', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdPrompt(page, title: 'Name', initialValue: 'old');
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(field.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(EditableText), 'new');
      // Return in a field reaches it as the platform's "done".
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await answer, 'new');
    });

    testWidgets('Return in a field does not also do the default', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      var defaults = 0;
      showBirdDialog<void>(
        context: page,
        builder: (context) => BirdDialog(
          title: 'Form',
          content: const BirdTextField(autofocus: true),
          actions: [BirdDialogAction('Go', isDefault: true, onPressed: () => defaults++)],
        ),
      ).ignore();
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.enter);
      expect(defaults, 0);
    });

    testWidgets('Escape from a prompt answers nothing', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      final answer = showBirdPrompt(page, title: 'Name', initialValue: 'old');
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(await answer, isNull);
    });
  });

  group('menus', () {
    List<BirdMenuEntry> entries(List<String> chosen) => [
      const BirdMenuItem.separator(),
      BirdMenuItem('New Tab', shortcut: '⌘T', onSelected: () => chosen.add('tab')),
      BirdMenuItem('Paste', enabled: false, onSelected: () => chosen.add('paste')),
      const BirdMenuItem.separator(),
      const BirdMenuItem.separator(),
      BirdMenuItem('More', submenu: [BirdMenuItem('Reload', onSelected: () => chosen.add('reload'))]),
      BirdMenuItem('Settings', onSelected: () => chosen.add('settings')),
      const BirdMenuItem.separator(),
    ];

    test('separators that separate nothing are dropped', () {
      final tidy = tidyMenuEntries(entries([])).cast<BirdMenuItem>().toList();
      expect(tidy.map((e) => e.isSeparator ? '-' : e.label), ['New Tab', 'Paste', '-', 'More', 'Settings']);
    });

    testWidgets('choosing closes the menu and does the thing', (tester) async {
      final chosen = <String>[];
      final page = await pumpApp(tester, (_) => const SizedBox());
      showBirdMenu(page, const Offset(40, 40), entries(chosen)).ignore();
      await tester.pumpAndSettle();
      expect(BirdMenus.isOpen, isTrue);
      await tester.tap(find.text('New Tab'));
      await tester.pumpAndSettle();
      expect(chosen, ['tab']);
      expect(find.text('New Tab'), findsNothing);
      expect(BirdMenus.isOpen, isFalse);
    });

    testWidgets('the arrows skip what cannot be chosen and open submenus', (tester) async {
      final chosen = <String>[];
      final page = await pumpApp(tester, (_) => const SizedBox());
      showBirdMenu(page, const Offset(40, 40), entries(chosen)).ignore();
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.enter);
      expect(chosen, ['reload']);
    });

    testWidgets('typing a letter goes to the item that starts with it', (tester) async {
      final chosen = <String>[];
      final page = await pumpApp(tester, (_) => const SizedBox());
      showBirdMenu(page, const Offset(40, 40), entries(chosen)).ignore();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await key(tester, LogicalKeyboardKey.enter);
      expect(chosen, ['settings']);
    });

    testWidgets('a menu at the right edge opens leftwards from its button', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        (_) => Align(
          alignment: Alignment.topRight,
          child: Builder(
            builder: (context) => BirdToolbarButton(
              glyph: BirdGlyph.menu,
              onPressed: () => showBirdMenuBelow(context, entries([])),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(BirdToolbarButton));
      await tester.pumpAndSettle();
      final row = tester.getRect(find.text('New Tab'));
      expect(row.right, lessThan(800));
      expect(row.left, greaterThan(500));
    });

    testWidgets('a select offers its options and reports the new one', (tester) async {
      var value = 'ask';
      await pumpApp(
        tester,
        (_) => StatefulBuilder(
          builder: (context, setState) => BirdSelect<String>(
            value: value,
            options: const [BirdOption('ask', 'Ask'), BirdOption('allow', 'Allow')],
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(value, 'allow');
      expect(find.text('Allow'), findsOneWidget);
    });
  });

  group('popovers', () {
    late OverlayPortalController controller;
    var dismissed = 0;

    Future<BuildContext> pumpPopover(WidgetTester tester) async {
      controller = OverlayPortalController();
      dismissed = 0;
      late BuildContext inside;
      await pumpApp(
        tester,
        (_) => BirdPopover(
          controller: controller,
          onDismiss: () => dismissed++,
          popoverBuilder: (context) {
            inside = context;
            return BirdPanel(
              width: 220,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('inside'),
                  BirdSelect<int>(
                    value: 1,
                    options: const [BirdOption(1, 'One'), BirdOption(2, 'Two')],
                    onChanged: (_) {},
                  ),
                ],
              ),
            );
          },
          child: BirdButton('Open', onPressed: () => controller.toggle()),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return inside;
    }

    testWidgets('hangs below its button', (tester) async {
      await pumpPopover(tester);
      expect(tester.getRect(find.text('inside')).top, greaterThan(tester.getRect(find.text('Open')).bottom));
    });

    testWidgets('a press outside hides it, and a press inside does not', (tester) async {
      await pumpPopover(tester);
      await tester.tap(find.text('inside'));
      await tester.pumpAndSettle();
      expect(controller.isShowing, isTrue);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(controller.isShowing, isFalse);
      expect(dismissed, 1);
    });

    testWidgets('its own button closes it once', (tester) async {
      await pumpPopover(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(controller.isShowing, isFalse);
    });

    testWidgets('Escape hides it', (tester) async {
      await pumpPopover(tester);
      await key(tester, LogicalKeyboardKey.escape);
      expect(controller.isShowing, isFalse);
    });

    testWidgets('choosing from a menu in it leaves it open', (tester) async {
      await pumpPopover(tester);
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(controller.isShowing, isTrue);
    });

    testWidgets('answering a dialog opened from it leaves it open', (tester) async {
      final inside = await pumpPopover(tester);
      final answer = showBirdConfirm(inside, title: 'Add it?', confirmLabel: 'Add');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
      expect(controller.isShowing, isTrue);
    });
  });

  group('left behind', () {
    testWidgets('a menu torn down with its window is not open any more', (tester) async {
      final page = await pumpApp(tester, (_) => const SizedBox());
      var closed = false;
      showBirdMenu(page, const Offset(40, 40), [BirdMenuItem('One', onSelected: () {})]).then((_) => closed = true);
      await tester.pumpAndSettle();
      expect(BirdMenus.isOpen, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(BirdMenus.isOpen, isFalse);
      expect(closed, isTrue);
    });
  });

  group('controls', () {
    testWidgets('pressing a button leaves the keyboard where it was', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var presses = 0;
      await pumpApp(
        tester,
        (_) => Column(
          children: [
            Focus(focusNode: node, autofocus: true, child: const SizedBox(width: 20, height: 20)),
            BirdToolbarButton(glyph: BirdGlyph.reload, onPressed: () => presses++),
          ],
        ),
      );
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await tester.tap(find.byType(BirdToolbarButton), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(presses, 1);
      expect(node.hasFocus, isTrue);
    });

    testWidgets('a press at the top edge of a field lands in it', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpApp(tester, (_) => SizedBox(width: 200, child: BirdTextField(focusNode: node)));
      final box = tester.getRect(find.byType(BirdTextField));
      await tester.tapAt(Offset(box.center.dx, box.top + 3), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
    });

    testWidgets('a disabled button does nothing', (tester) async {
      await pumpApp(tester, (_) => const BirdButton('No', onPressed: null));
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
    });

    testWidgets('a checkbox is pressed by its words', (tester) async {
      var value = false;
      await pumpApp(
        tester,
        (_) => StatefulBuilder(
          builder: (context, setState) =>
              BirdCheckbox(value: value, label: 'Remember', onChanged: (next) => setState(() => value = next)),
        ),
      );
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('a search field empties on Escape and by its button', (tester) async {
      final seen = <String>[];
      await pumpApp(tester, (_) => SizedBox(width: 240, child: BirdSearchField(onChanged: seen.add, autofocus: true)));
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.escape);
      expect(seen.last, '');
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BirdToolbarButton));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    });
  });
}
