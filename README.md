# Rubisco Browser

![Rubisco Browser](https://github.com/user-attachments/assets/d11eb314-bdc9-4ada-9c1e-2e8b19746268)

A Flutter-based browser, built on Ladybird

## Try it out
You can currently try in on Android and macOS. Linux support will come soon, and Windows will come later. iOS support *may* arrive for EU users sometime later.

You can download an APK in the [Actions section](https://github.com/rubiscolabs/rubisco-browser/actions)

**Security Note**: Ladybird was built with good security as a base, however, browsers are complex, so there is a very high chance security issues exist that have not been discovered. Use at your own risk, and don't be reckless. 

## Developing Locally
Currently, there's going to be a lot of work needed to run this. Later down the line I plan on having ladybird build remotely and just download the objects at compile, but for now a lot of hoops need to be jumped through.
***I strongly recommend you familiarize yourself with ladybird itself before working with rubisco browser***.

You will need flutter master, with the new windowing api experiment enabled.

When doing a clean build of Rubisco Browser on any device, you may run into build errors in general. What I recommend you to is to navigate to `packages/libbird/third_party/ladybird/Meta` and run `ladybird.py run`, if this happens. This will isolate any build issues, since there's a lot that can go wrong here.

There is a system to download prebuilt objects for Android and macOS, however, I do not default to that as they may not always be available. If you would like to try this, create or edit the native_mode.local file in `packages/libbird`, and set the contents to `prebuilt`. You can switch between compiling locally by changing that file contents to `local`. Later I will default to downloading objects, as compiling ladybird is a bit of a task and requires a lot of environment configuration.

## Support / Completeness
Development is rapid, between both Rubisco Browser and Ladybird, so this may be out of date. Features generally are as follows;

- 🟩 General browsing on Android and macOS, multiple tab support
- 🟩 Multi window, split off and merge tabs between different windows
- 🟨 Devtools; most things are implemented, however not everything is supported by Ladybird
- 🟨 Keyboard shortcuts; some are supported like CMD+T, but some are not like CMD+R, etc
- 🟨 Extensions; supports firefox extensions, however the implementation is not complete so some extensions have problems
- 🟨 Permissions; microphone, camera, location, etc, support depends on the platform
- 🟨 General web compatibility; This uses [Ladybird](https://github.com/LadybirdBrowser/ladybird), which has made very good progress, but is very new and has known issues across websites
- 🟨 Bookmarks. They exist but are not complete
- 🟥 Drag and drop
- 🟥 DRM Support (Youtube TV, etc). Websites that use DRM for video playback don't work currently. I am attempting to get access to Widevine, however access to such is notoriously not guaranteed. I may look into other avenues for playing DRM content.

And in general, there's going to be a lot of quirks for a while that are difficult to categorize. Even if I labeled something as unsupported, do feel free to make a [new issue](https://github.com/rubiscolabs/rubisco-browser/issues/new), such that I can prioritze and gather interest. 


