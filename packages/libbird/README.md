# Ladybird
An ***unofficial*** project to embed the Ladybird browser in your Flutter app.

## How to integrate
We currently only support **MacOS**. Linux support will begin shortly as we get the groundwork in-place, then we will target new platforms as Ladybird supports.

## Status
This project is ***very*** early. 

## How to use
1. Run `flutter pub add ladybird`
2. Build a basic window, following the `example.dart`
3. `flutter run -d macos`
Note: This clones Ladybird into `third_party/ladybird`, pins it to the revision in `third_party/ladybird.version`, and then builds it locally with the official `ladybird.py` script. I recommend navigating to the `macos` folder in your app, and running `pod install`,
as when flutter runs `pod install` automatically you cannot see build process. This will take a while! Compiling a web browser takes a lot of time.

To update Ladybird to a newer upstream commit, rebase `LADYBIRD_REF` in `third_party/ladybird.version` (the fork's `feat/flutterbird` branch, which is upstream master plus libbird's embedding hooks) onto upstream master, then set `LADYBIRD_REVISION` to the resulting commit and rerun your build. `libbird` will fetch the repository and move the checkout to the new pinned revision automatically.

## Checking the embedding after moving the Ladybird pin
`tool/engine_smoke_check.dart` drives the engine's C ABI directly (no Flutter, no window) and
checks that navigation, painting and wheel input still reach the page:

```sh
flutter build macos --debug
APP=build/macos/Build/Products/Debug/flutterbird.app
mkdir -p /tmp/libbird-home && ln -sfn "$PWD/packages/libbird/third_party/ladybird/Base/res" /tmp/libbird-home/.lagom
(cd "$APP/Contents/MacOS" && HOME=/tmp/libbird-home dart run \
    ../../../packages/libbird/tool/engine_smoke_check.dart "$APP/Contents/Resources/libengine.dylib")
```

The ABI is positional, so an engine change that renumbers an event type (Ladybird inserted
`MouseCancel` before `MouseWheel`, which silently turned every wheel event into a cancel) breaks
scrolling with no compile error. `engine.h` therefore defines its own event-type names and
`engine.cpp` maps them onto the engine's, and this check catches the rest.

## What is supported
- Launching a browser window on MacOS
- Basic navigation
- Interacting with web pages
- Scrolling

## What needs to be supported
- Linux
- Some window jank
- Content bindings (running JS, etc)
- Multi-window tabs
- Callbacks for creating new tabs, etc

It should also be noted that ladybird itself is very early, so you'll encounter a mix of issues introduced by both this library and Ladybird.

## Why?
Mostly because it's fun. I want to learn more low level Flutter stuff with Textures and such. Also, Ladybird is cool to work with and I am looking to implement [FlutterBird](github.com/EricApostal/flutterbird), a *creatively named* Flutter-based frontend for Ladybird.
