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

## Native builds: compile locally, or use a prebuilt copy
Compiling Ladybird and the engine takes hours. For macOS (Apple Silicon) and Android (arm64) a
prebuilt copy of the native code can be used instead, which makes a build take minutes and needs no
C++ toolchain, Rust, or Ladybird checkout.

Pick one with `LIBBIRD_NATIVE_MODE`:

| Mode       | What happens                                                                                  |
|------------|-----------------------------------------------------------------------------------------------|
| `local`    | Compile here. This is the default, and what the sections above describe.                    |
| `prebuilt` | Use the copy built by CI. Fails with a message if there is none, rather than quietly compiling. |
| `auto`     | Use the copy if there is one for this exact source, and compile otherwise.                    |

```sh
LIBBIRD_NATIVE_MODE=prebuilt flutter run -d macos --release
```

To make a machine always use one, put the word in `packages/libbird/native_mode.local` (ignored by
git). The environment variable wins over the file. Switching back and forth is safe: each platform
build clears what the other left behind.

### Which copy is the right one
A copy is only valid for the source it was built from, so it is looked up by a *fingerprint* of the
pinned Ladybird revision (`third_party/ladybird.version`) and the engine's own sources (`cpp/`, the
Android CMake file and JNI sources, the podspec). Print it with:

```sh
packages/libbird/tool/libbird_native.sh fingerprint
```

Changing any of those gives a new fingerprint, so a stale copy is never used. Flutter-side code (Dart,
Swift, the Android plugin's Java) is compiled by your app in both modes and is not part of it. The one
exception is the Java plugin's `native` method signatures, which have to match the engine: if you
change them, build a new copy, or use `local`.

Copies are downloaded from the release `libbird-native-<fingerprint>` of
`EricApostal/flutterbird`, verified against their SHA-256, and cached in
`~/.cache/libbird-native`. For a fork or a mirror, set `LIBBIRD_NATIVE_REPO` or
`LIBBIRD_NATIVE_BASE_URL`. A private repository works if the GitHub CLI (`gh`) is signed in.

### Publishing copies
The `Native artifacts` workflow (`.github/workflows/native-artifacts.yml`) builds a copy for each
platform and attaches it to the release for the current fingerprint. It runs when the engine or the
Ladybird pin changes on `main`, skips platforms that already have a copy, and can be started by hand
(with `force` to rebuild one that exists). After moving the pin or changing the engine, wait for it
before using `prebuilt` or `auto`.

What is in a copy:
- **macOS:** the contents of `cpp/build/LadybirdBundle` (the engine, Ladybird's libraries, its helper
  processes, resources and ICU data), unpacked into the same place a local build puts them.
- **Android:** the native libraries a local build packages (the engine, the plugin, the helper
  processes, the C++ runtime), plus Ladybird's assets and the SDL3 Java sources, unpacked into the
  Gradle build's `generated/` directory.

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
