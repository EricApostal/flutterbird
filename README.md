# Rubisco Browser

![Rubisco Browser](https://github.com/user-attachments/assets/d11eb314-bdc9-4ada-9c1e-2e8b19746268)

A Flutter-based browser, based on Ladybird

## Try it out
You can currently try in on Android and macOS. Linux support will come soon, and Windows will come later. iOS support *may* arrive for EU users sometime later.

You can download an APK in the [Actions section](https://github.com/rubiscolabs/rubisco-browser/actions)

## Developing Locally
Currently, there's going to be a lot of work needed to run this. Later down the line I plan on having ladybird build remotely and just download the objects at compile, but for now a lot of hoops need to be jumped through.
***I strongly recommend you familiarize yourself with ladybird itself before working with rubisco browser***.

When doing a clean build of Rubisco Browser on any device, you may run into build errors in general. What I recommend you to is to navigate to `packages/libbird/third_party/ladybird/Meta` and run `ladybird.py run`, if this happens. This will isolate any build issues, since there's a lot that can go wrong here.

There is a system to download prebuilt objects for Android and macOS, however, I do not default to that as they may not always be available. If you would like to try this, create or edit the native_mode.local file in `packages/libbird`, and set the contents to `prebuilt`. You can switch between compiling locally by changing that file contents to `local`. Later I will default to downloading objects, as compiling ladybird is a bit of a task and requires a lot of environment configuration.
