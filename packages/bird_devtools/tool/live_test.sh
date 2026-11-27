#!/usr/bin/env bash
# Runs a test against a fresh headless Ladybird, then stops that engine.
#
#   tool/live_test.sh [test file ...]
#
# LADYBIRD_APP names a built Ladybird.app; FLUTTER the flutter command.
set -euo pipefail

PACKAGE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${PACKAGE}/../libbird/third_party/ladybird/Build/release"
APP="${LADYBIRD_APP:-${BUILD}/bin/Ladybird.app}"
FLUTTER="${FLUTTER:-flutter}"
HTTP_PORT="${HTTP_PORT:-8766}"
DEVTOOLS_PORT="${DEVTOOLS_PORT:-6791}"
WORK="$(mktemp -d)"

python3 -m http.server "${HTTP_PORT}" --bind 127.0.0.1 \
  --directory "${PACKAGE}/test/site" >"${WORK}/http.log" 2>&1 &
HTTP_PID=$!

cleanup() {
  kill "${HTTP_PID}" "${ENGINE_PID:-}" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

for _ in $(seq 50); do
  curl -s -o /dev/null "http://127.0.0.1:${HTTP_PORT}/index.html" && break
  sleep 0.1
done

DYLD_FRAMEWORK_PATH="${BUILD}/vcpkg_installed/arm64-osx-dynamic/Frameworks" \
  "${APP}/Contents/MacOS/ladybird" --headless=manual --temporary-profile \
  --devtools="${DEVTOOLS_PORT}" --window-width 1000 --window-height 700 \
  "http://127.0.0.1:${HTTP_PORT}/index.html" >"${WORK}/engine.log" 2>&1 &
ENGINE_PID=$!

for _ in $(seq 100); do
  nc -z 127.0.0.1 "${DEVTOOLS_PORT}" 2>/dev/null && break
  sleep 0.1
done

cd "${PACKAGE}"
BIRD_DEVTOOLS_PORT="${DEVTOOLS_PORT}" \
  BIRD_DEVTOOLS_PAGE="http://127.0.0.1:${HTTP_PORT}/index.html" \
  "${FLUTTER}" test "${@:-test/live_engine_test.dart}"
