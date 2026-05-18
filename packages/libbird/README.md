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

To update Ladybird to a newer upstream commit, change `LADYBIRD_REVISION` in `third_party/ladybird.version` and rerun your build. `libbird` will fetch the repository and move the checkout to the new pinned revision automatically.

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
