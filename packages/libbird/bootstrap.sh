#!/bin/bash
set -e

echo "Building Ladybird..."
cd third_party/ladybird
./Meta/ladybird.py build
cd ../..

echo "Staging artifacts for SPM..."
ARTIFACTS_DIR="macos/LadybirdArtifacts"

# Clean any previous artifacts
rm -rf "$ARTIFACTS_DIR"

mkdir -p "$ARTIFACTS_DIR/lib"
mkdir -p "$ARTIFACTS_DIR/helpers"
mkdir -p "$ARTIFACTS_DIR/resources"
mkdir -p "$ARTIFACTS_DIR/include"

# The compiled app bundle is our source of truth
APP_CONTENTS="third_party/ladybird/Build/release/bin/Ladybird.app/Contents"

# 1. Copy dynamic libraries
cp -R "$APP_CONTENTS/lib/"* "$ARTIFACTS_DIR/lib/"

# 2. Copy the helper executables
cp "$APP_CONTENTS/MacOS/WebContent" "$ARTIFACTS_DIR/helpers/"
cp "$APP_CONTENTS/MacOS/RequestServer" "$ARTIFACTS_DIR/helpers/"
cp "$APP_CONTENTS/MacOS/ImageDecoder" "$ARTIFACTS_DIR/helpers/"
cp "$APP_CONTENTS/MacOS/WebWorker" "$ARTIFACTS_DIR/helpers/"

# 3. Copy required browser resources
cp -R "$APP_CONTENTS/Resources/"* "$ARTIFACTS_DIR/resources/"

# 4. Symlink the headers to bypass SPM sandbox rules
echo "Symlinking headers for SPM..."
cd "$ARTIFACTS_DIR/include"
ln -sf "../../../third_party/ladybird" "ladybird_src"
ln -sf "../../../third_party/ladybird/Build/release" "ladybird_build"
cd ../../..

echo "✅ Artifacts and symlinks staged for SPM."