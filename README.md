# FlutterBird

A Flutter-based browser, based on Ladybird

Mostly just a toy project to learn embedded Flutter views

## Developing
Currently, there's going to be a lot of work needed to run this. Later down the line I plan on having ladybird build remotely and just download the objects at compile, but for now a lot of hoops need to be jumped through.
***I strongly recommend you familiarize yourself with ladybird itself before working with flutterbird***.

`packages/libbird` drives Ladybird through a small C ABI (`packages/libbird/cpp/engine.h`)
over `WebView::ViewImplementation`. It builds Ladybird from a pinned checkout: on the first
native build, `packages/libbird/tool/ensure_ladybird_source.sh` clones
`third_party/ladybird.version`'s repository/ref/revision into
`packages/libbird/third_party/ladybird`, and CMake then runs Ladybird's own
`Meta/ladybird.py build` before compiling the wrapper.

That pin is the `feat/flutterbird` branch of the fork
(`https://github.com/EricApostal/ladybird`), which is upstream master plus the few
embedding hooks libbird needs — never a stale snapshot of Ladybird with months of
drift in it. To move to a newer Ladybird, rebase that branch onto upstream master,
build it, then update `LADYBIRD_REVISION` in `third_party/ladybird.version` (and the
`third_party/ladybird` gitlink) to the new commit.

When doing a clean build of FlutterBird on any device, you may run into build errors in general. What I recommend you to is to navigate to `packages/libbird/third_party/ladybird/Meta` and run `ladybird.py run`, if this happens. This will isolate any build issues, since there's a lot that can go wrong here. The first build takes a long time: it bootstraps vcpkg (pinned by Ladybird's `vcpkg.json`) and compiles all of Ladybird.

### Linux & Android
I am not aware of any specific quirks with these, just try targeting them when selecting the flutter device.

On Linux the engine also builds Ladybird's Vulkan dmabuf path when the Ladybird build enables
`USE_VULKAN_DMABUF_IMAGES`, which is what the GTK plugin imports for zero-copy frames; otherwise
it falls back to copying the presented bitmap.

On Android the helper processes are packaged as `lib<Name>.so` in the app's native library
directory, so the fork's helper lookup knows to look for them there, and frames reach Flutter as
`AHardwareBuffer`s that `libbird` allocates and fills itself (Ladybird no longer produces
hardware buffers of its own).

### MacOS
Due to the aforementioned bug in xcode beta, make sure you are targeting the stable version of xcode

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Ladybird's macOS build enables its GUI targets, so a Qt 6.10+ installation is required
(`brew install qt`) in addition to Xcode. Frames reach Flutter as IOSurfaces wrapped into
`CVPixelBuffer`s, with a bitmap fallback if the IOSurface is not available yet.