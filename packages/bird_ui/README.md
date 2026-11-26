# bird_ui

The browser's desktop widgets: shaped like Firefox's, with macOS manners and
Rubisco's own colours, built on
`package:flutter/widgets.dart` with no Material. The developer tools
(`bird_devtools`) use its menus, tooltips, text editing, icons and scrolling.
Android's interface is still Material, from `package:material_ui`.

To see every component, show a `BirdGallery` (`package:bird_ui/gallery.dart`),
or take pictures of it in both themes:

```sh
BIRD_UI_SHOTS=/tmp/shots flutter test test/screenshots_test.dart
```

## What to reach for

| You need | Use |
| --- | --- |
| A window's root | `BirdApp`, `BirdApp.router` |
| A message, a yes or no, a line of text | `showBirdAlert`, `showBirdConfirm`, `showBirdPrompt` |
| Any other dialog | `showBirdDialog` with a `BirdDialog` |
| A context menu, or a button's menu | `showBirdMenu`, `showBirdMenuBelow` |
| A panel that hangs from a button | `BirdPopover` with a `BirdPanel`, `BirdPanelHeader` and `BirdListRow` |
| Buttons | `BirdButton`, `BirdToolbarButton`, `BirdLink` |
| Fields | `BirdTextField`, `BirdSearchField`; `BirdTextInput` to draw your own box |
| Choices | `BirdCheckbox`, `BirdRadio`, `BirdSwitch`, `BirdSelect` |
| Status | `BirdProgressBar`, `BirdSpinner`, `BirdBadge`, `BirdMessageBar`, `BirdPlaceholder` |
| Something custom that can be pressed | `BirdPressable` |

Colours come from `context.bird`, and text from `context.birdText(...)`. Add a
colour to `BirdColors` rather than writing one into a widget.

The palette is made from the two colours of the mark, `BirdBrand.blue` and
`BirdBrand.ink`: the greys are tinted with the ink, `accent` is the blue as a
fill, and `link` is the blue as words and marks, which differs between themes
so that it can be read. Text keeps a contrast of at least 4.5 to 1 on what it
sits on. The developer tools have their own table, `DtColors`, with the same
greys and a set of colours for code. Icons are drawn
in `lib/src/icons.dart` on a 16 by 16 grid.

Whether the app is light or dark is `desktopThemeMode` in
`lib/features/theme/appearance.dart` of the app.

## Dialogs

```dart
final remove = await showBirdConfirm(
  context,
  title: 'Remove uBlock Origin?',
  message: 'Its settings are removed with it.',
  confirmLabel: 'Remove',
  destructive: true,
);
```

Buttons are listed in macOS's order, with the one that goes ahead last. Escape
cancels. Return presses the focused button, or else the action marked
`isDefault`. Do not mark one that destroys or grants something, so that a key
already on its way cannot do it; give the way out `autofocus` instead. In a
text field, Return is the field's, so submit from `onSubmitted`.

## Manners the components keep

- A click on a button does not take the keyboard from what has it. Tab still
  reaches every button, and shows a focus ring.
- A `BirdPopover` closes on a press outside it, but not on one in a menu or
  dialog opened from it. Set `takeFocus: false` for one that opens by itself.
- Menus skip disabled items, take arrow keys and typed letters, and open
  submenus.
