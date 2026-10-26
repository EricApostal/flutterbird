# FlutterBird

A Flutter-based browser, based on Ladybird

Mostly just a toy project to learn embedded Flutter views

## Developing
Currently, there's going to be a lot of work needed to run this. Later down the line I plan on having ladybird build remotely and just download the objects at compile, but for now a lot of hoops need to be jumped through.
***I strongly recommend you familiarize yourself with ladybird itself before working with flutterbird***.

When doing a clean build of FlutterBird on any device, you may run into build errors in general. What I recommend you to is to navigate to `packages/libbird/third_party/ladybird/Meta` and run `ladybird.py run`, if this happens. This will isolate any build issues, since there's a lot that can go wrong here.

### Linux & Android
I am not aware of any specific quirks with these, just try targeting them when selecting the flutter device.

### MacOS
Due to the aforementioned bug in xcode beta, make sure you are targeting the stable version of xcode

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### iOS
> [!WARNING]
> iOS does run, however, it's more of a proof of concept than anything. While the EU is requiring Apple to allow 3rd party browser engines, those APIs, even for development purposes, require explicit approval from apple to use. I use a heavily modified fork of ladybird that includes single-process support for iOS, meaning that it's much less secure and stable. Libbird, and by extension FlutterBird, cannot be published to the app store, even in the EU, as it does not comply with Apple's browser engine policies.

When building to beta versions of iOS (ie: iOS 26), you will need to use the beta version of xcode. However, if you plan on targeting macos, there is an apparant bug in the xcode beta that prevents you from targeting release mode. For iOS development, you need to set it to the following

```sh
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```