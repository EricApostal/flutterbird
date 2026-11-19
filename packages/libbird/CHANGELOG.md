## 0.0.1
* Implement very basic foundation spawning instances and interfacing with Ladybird on MacOS

## 0.0.4
* Many window fixes, input support, implement tabs

## Unreleased
* Native code can be compiled locally or taken from a prebuilt copy (macOS arm64, Android arm64-v8a):
  `LIBBIRD_NATIVE_MODE=local|prebuilt|auto`, or `native_mode.local`. See "Native builds" in the README.
* The `Native artifacts` workflow builds those copies and attaches them to a release per source fingerprint.
* Android: `SystemProbe` is built and packaged, which GPU painting depends on.

