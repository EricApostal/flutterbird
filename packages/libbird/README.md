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
Note: This builds ladybird locally then bundles it into your app. It works by running the official `ladybird.py` script. I recommend navigating to the `macos` folder in your app, and running `pod install`,
as when flutter runs `pod install` automatically you cannot see build process. This will take a while! Compiling a web browser takes a lot of time.

## What is supported
- Launching a browser window on MacOS
- Basic navigation

## What needs to be supported
- Linux
- Many window fixes
- Interfacing with the web content (typing, scrolling, etc)
- Content bindings (running JS, page change callbacks, etc)

It should also be noted that ladybird itself is very early, so you'll encounter a mix of issues introduced by both this library and Ladybird.

## Why?
Mostly because it's fun. I want to learn more low level Flutter stuff with Textures and such. Also, Ladybird is cool to work with and I am looking to implement [FlutterBird](github.com/EricApostal/flutterbird), a *creatively named* Flutter-based frontend for Ladybird.
