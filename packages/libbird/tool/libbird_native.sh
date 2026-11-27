#!/usr/bin/env bash
# Chooses between compiling libbird's native code (Ladybird and the engine) and
# using a prebuilt copy of it, and fetches or packages the prebuilt copy.
#
# Every build step that has to decide (the macOS pod, the Android Gradle build,
# the Dart build hook) asks this script, so the decision is made one way.
#
#   libbird_native.sh mode [platform]           local or prebuilt, as resolved
#   libbird_native.sh fingerprint               what a prebuilt copy must match
#   libbird_native.sh tag                       the release that holds it
#   libbird_native.sh asset-name <platform>     the file for a platform
#   libbird_native.sh fetch <platform> <dest>   download, verify and unpack it
#   libbird_native.sh package <platform> <src> <out-dir>
#                                               pack a build's output (CI)
#
# Platforms: macos-arm64, android-arm64-v8a.
#
# The mode comes from, in this order:
#   1. the LIBBIRD_NATIVE_MODE environment variable,
#   2. a one-word file, packages/libbird/native_mode.local (ignored by git),
#   3. "local".
# and is one of:
#   local     compile Ladybird and the engine here. Needs the toolchains, takes
#             hours the first time.
#   prebuilt  use the copy built by CI for this exact source (see "fingerprint").
#             Fails when there is none, rather than quietly compiling.
#   auto      prebuilt when there is a copy for this exact source, else local.
#
# Other settings:
#   LIBBIRD_NATIVE_REPO      GitHub repository whose releases hold the copies
#   LIBBIRD_NATIVE_BASE_URL  where releases are downloaded from, for a mirror
#   LIBBIRD_NATIVE_CACHE     where downloads are kept between builds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PACKAGE_ROOT}/third_party/ladybird.version"

REPOSITORY="${LIBBIRD_NATIVE_REPO:-EricApostal/flutterbird}"
BASE_URL="${LIBBIRD_NATIVE_BASE_URL:-https://github.com/${REPOSITORY}/releases/download}"
CACHE_DIR="${LIBBIRD_NATIVE_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/libbird-native}"

# Written next to what a fetch unpacks, so that the next one can tell it is there.
STAMP_NAME=".libbird-native-fingerprint"
MANIFEST_NAME="LIBBIRD_NATIVE.json"

# Everything an Android copy holds, besides the sources and assets: the engine,
# the plugin that loads it, the C++ runtime, and the helper processes (found by
# the engine as lib<Name>.so in the app's native library directory).
ANDROID_NATIVE_LIBS=(
  libengine.so
  libladybird_plugin.so
  libc++_shared.so
  libladybird-audio.so
  libladybird-gpu.so
  libladybird-image.so
  libladybird-media.so
  libladybird-net.so
  libladybird-probe.so
  libladybird-render.so
  libladybird-video.so
)

# Temporary directories made along the way, removed when the script ends however
# it ends. (An empty array is an error under `set -u` in the bash 3.2 that macOS
# ships, hence the odd expansion.)
TEMP_DIRS=()
cleanup() {
  if ((${#TEMP_DIRS[@]} > 0)); then
    rm -rf "${TEMP_DIRS[@]}"
  fi
}
trap cleanup EXIT

log() { echo "libbird-native: $*" >&2; }
die() {
  log "error: $*"
  exit 1
}

sha256_of_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

validate_platform() {
  case "$1" in
    macos-arm64 | android-arm64-v8a) ;;
    *) die "unknown platform '$1' (expected macos-arm64 or android-arm64-v8a)" ;;
  esac
}

ladybird_revision() {
  [[ -f "${VERSION_FILE}" ]] || die "missing ${VERSION_FILE}"
  local revision
  revision="$(sed -n 's/^LADYBIRD_REVISION=//p' "${VERSION_FILE}" | head -n 1 | tr -d '[:space:]')"
  [[ -n "${revision}" ]] || die "no LADYBIRD_REVISION in ${VERSION_FILE}"
  echo "${revision}"
}

# What a prebuilt copy has to match to be the one a local build would have made:
# the Ladybird revision, and the engine's own sources and build files. The
# Flutter-side code (Dart, Swift, the plugin's Java) is compiled by the app
# either way, so it is not part of this. Changing a `native` method in the Java
# plugin does mean rebuilding the copy, which shows up as an
# UnsatisfiedLinkError, not as silent breakage.
native_fingerprint() {
  local revision
  revision="$(ladybird_revision)"
  (
    cd "${PACKAGE_ROOT}"
    echo "ladybird_revision=${revision}"
    fingerprint_files | LC_ALL=C sort -u | while IFS= read -r file; do
      [[ -f "${file}" ]] || continue
      printf '%s  %s\n' "$(sha256_of_file "${file}")" "${file}"
    done
  ) | sha256_of_stdin | cut -c1-16
}

# The files the fingerprint covers, relative to the package root. In a git
# checkout that is what git knows of them, tracked or not yet added, so that
# whatever a machine leaves lying around (clangd's cache, build output, editor
# files) cannot make its fingerprint differ from CI's. Without git, as when the
# package comes from pub.dev, it is what is there.
fingerprint_files() {
  local paths=(cpp android/src/main/cpp android/CMakeLists.txt macos/ladybird.podspec)
  if git -C "${PACKAGE_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${PACKAGE_ROOT}" ls-files --cached --others --exclude-standard -- "${paths[@]}"
  else
    local path
    for path in "${paths[@]}"; do
      [[ -e "${PACKAGE_ROOT}/${path}" ]] || continue
      (cd "${PACKAGE_ROOT}" && find "${path}" -type f \
        -not -path 'cpp/build/*' -not -path 'cpp/.cache/*' -not -name '.DS_Store')
    done
  fi
}

release_tag() { echo "libbird-native-$1"; }
asset_name() { echo "libbird-native-$1-$2.tar.gz"; }

requested_mode() {
  local value="${LIBBIRD_NATIVE_MODE:-}"
  if [[ -z "${value}" && -f "${PACKAGE_ROOT}/native_mode.local" ]]; then
    value="$(tr -d '[:space:]' <"${PACKAGE_ROOT}/native_mode.local")"
  fi
  value="${value:-local}"
  case "${value}" in
    local | prebuilt | auto) echo "${value}" ;;
    *) die "unknown native mode '${value}' (expected local, prebuilt or auto)" ;;
  esac
}

# Whether the release for this source has the copy for a platform.
asset_exists() {
  local platform="$1" fingerprint asset tag
  fingerprint="$(native_fingerprint)"
  asset="$(asset_name "${platform}" "${fingerprint}")"
  tag="$(release_tag "${fingerprint}")"
  # A one-byte ranged GET rather than a HEAD: release downloads redirect to
  # storage links that are signed for GET only.
  if curl -fsSL --max-time 15 -r 0-0 -o /dev/null "${BASE_URL}/${tag}/${asset}" 2>/dev/null; then
    return 0
  fi
  # A private repository answers curl with a 404, and the GitHub CLI, if it is
  # signed in, is how to see in.
  if command -v gh >/dev/null 2>&1 &&
    gh release view "${tag}" -R "${REPOSITORY}" --json assets -q '.assets[].name' 2>/dev/null |
    grep -qx "${asset}"; then
    return 0
  fi
  return 1
}

resolved_mode() {
  local platform="${1:-}" requested
  requested="$(requested_mode)"
  if [[ "${requested}" != auto ]]; then
    echo "${requested}"
    return
  fi
  # Without a platform there is nothing to look for, and compiling is the choice
  # that works everywhere.
  if [[ -z "${platform}" ]]; then
    echo local
    return
  fi
  validate_platform "${platform}"
  if asset_exists "${platform}"; then
    echo prebuilt
  else
    log "no prebuilt copy of $(native_fingerprint) for ${platform}; compiling locally"
    echo local
  fi
}

verify_checksum() {
  local archive="$1" checksum_file="$2" expected actual
  [[ -f "${archive}" && -f "${checksum_file}" ]] || return 1
  expected="$(cut -d' ' -f1 <"${checksum_file}" | head -n 1)"
  actual="$(sha256_of_file "${archive}")"
  [[ -n "${expected}" && "${expected}" == "${actual}" ]]
}

download() {
  local tag="$1" name="$2" output="$3" scratch
  mkdir -p "$(dirname "${output}")"
  if curl -fSL --retry 3 --retry-delay 2 -o "${output}.part" "${BASE_URL}/${tag}/${name}" 2>/dev/null; then
    mv "${output}.part" "${output}"
    return 0
  fi
  rm -f "${output}.part"
  if command -v gh >/dev/null 2>&1; then
    scratch="$(mktemp -d)"
    if gh release download "${tag}" -R "${REPOSITORY}" -p "${name}" -D "${scratch}" --clobber >/dev/null 2>&1 &&
      [[ -f "${scratch}/${name}" ]]; then
      mv "${scratch}/${name}" "${output}"
      rm -rf "${scratch}"
      return 0
    fi
    rm -rf "${scratch}"
  fi
  return 1
}

required_entries() {
  case "$1" in
    macos-arm64)
      echo "libengine.dylib libraries binaries/ladybird-render binaries/ladybird-net res"
      ;;
    android-arm64-v8a)
      echo "ladybirdHelperJniLibs/arm64-v8a/libengine.so" \
        "ladybirdHelperJniLibs/arm64-v8a/libladybird_plugin.so" \
        "ladybirdHelperJniLibs/arm64-v8a/libladybird-render.so" \
        "ladybirdAssets/ladybird-assets.zip"
      ;;
  esac
}

# SDL's Android Java comes to the build in one of two forms: the sources, copied
# out of vcpkg's build tree (sdl3Java), or a jar that vcpkg packaged (sdl3Jar),
# which the Gradle build uses in place of the sources when there is one. A copy
# holds whichever form the build it was made from used, and needs one of them.
has_sdl3_java() {
  local root="$1"
  if [[ -d "${root}/sdl3Java" && -n "$(ls -A "${root}/sdl3Java" 2>/dev/null)" ]]; then
    return 0
  fi
  if compgen -G "${root}/sdl3Jar/*.jar" >/dev/null; then
    return 0
  fi
  return 1
}

check_required_entries() {
  local platform="$1" root="$2" entry missing=()
  for entry in $(required_entries "${platform}"); do
    [[ -e "${root}/${entry}" ]] || missing+=("${entry}")
  done
  if [[ "${platform}" == android-arm64-v8a ]] && ! has_sdl3_java "${root}"; then
    missing+=("SDL3 Java (sdl3Java or sdl3Jar)")
  fi
  if ((${#missing[@]} > 0)); then
    die "${root} is missing: ${missing[*]}"
  fi
}

fetch_artifact() {
  local platform="$1" dest="$2"
  validate_platform "${platform}"
  [[ -n "${dest}" ]] || die "fetch needs a destination"

  local fingerprint asset tag want
  fingerprint="$(native_fingerprint)"
  asset="$(asset_name "${platform}" "${fingerprint}")"
  tag="$(release_tag "${fingerprint}")"
  want="${platform}:${fingerprint}"

  if [[ -f "${dest}/${STAMP_NAME}" && "$(cat "${dest}/${STAMP_NAME}")" == "${want}" ]]; then
    log "the prebuilt ${platform} copy of ${fingerprint} is already in ${dest}"
    return 0
  fi

  local archive="${CACHE_DIR}/${asset}" checksum="${CACHE_DIR}/${asset}.sha256"
  if ! verify_checksum "${archive}" "${checksum}"; then
    rm -f "${archive}" "${checksum}"
    log "downloading ${asset}"
    download "${tag}" "${asset}" "${archive}" ||
      die "no prebuilt copy for ${platform} at ${fingerprint}: ${BASE_URL}/${tag}/${asset} was not found. Build it with the \"Native artifacts\" workflow, or set LIBBIRD_NATIVE_MODE=local to compile here (LIBBIRD_NATIVE_MODE=auto does that by itself when there is no copy)."
    download "${tag}" "${asset}.sha256" "${checksum}" ||
      die "the checksum for ${asset} was not found next to it"
    if ! verify_checksum "${archive}" "${checksum}"; then
      rm -f "${archive}" "${checksum}"
      die "${asset} does not match its checksum"
    fi
  fi

  mkdir -p "${dest}"
  # Clear what the copy brings and nothing else: an Android destination also
  # holds other generated files.
  local top
  while IFS= read -r top; do
    [[ -n "${top}" && "${top}" != "." ]] || continue
    rm -rf "${dest:?}/${top}"
  done < <(tar -tzf "${archive}" | sed 's#^\./##' | cut -d/ -f1 | sed '/^$/d' | LC_ALL=C sort -u)

  tar -xzf "${archive}" -C "${dest}"
  check_required_entries "${platform}" "${dest}"
  printf '%s' "${want}" >"${dest}/${STAMP_NAME}"
  log "unpacked the prebuilt ${platform} copy of ${fingerprint} into ${dest}"
}

package_android_stage() {
  local build_dir="$1" stage="$2"
  local ladybird_build="${build_dir}/ladybird"
  local apk="${LIBBIRD_NATIVE_APK:-${build_dir}/app/outputs/flutter-apk/app-release.apk}"

  [[ -f "${apk}" ]] || die "no APK at ${apk} (set LIBBIRD_NATIVE_APK)"
  [[ -f "${ladybird_build}/generated/ladybirdAssets/ladybird-assets.zip" ]] ||
    die "no ladybird-assets.zip under ${ladybird_build}/generated"

  local libs_dir="${stage}/ladybirdHelperJniLibs/arm64-v8a" lib
  mkdir -p "${libs_dir}" "${stage}/ladybirdAssets"
  for lib in "${ANDROID_NATIVE_LIBS[@]}"; do
    unzip -j -o -q "${apk}" "lib/arm64-v8a/${lib}" -d "${libs_dir}" ||
      die "${lib} is not in ${apk}"
  done
  cp "${ladybird_build}/generated/ladybirdAssets/ladybird-assets.zip" "${stage}/ladybirdAssets/"

  # SDL's Java, in the form the build used (see has_sdl3_java). A fresh vcpkg
  # build has the jar and never copies sources, which is why neither form can be
  # taken for granted.
  if [[ -d "${ladybird_build}/generated/sdl3Java" ]]; then
    cp -R "${ladybird_build}/generated/sdl3Java" "${stage}/sdl3Java"
  fi
  local ladybird_dir="${LIBBIRD_LADYBIRD_DIR:-${PACKAGE_ROOT}/third_party/ladybird}"
  local jar index=0
  # One form only: with the sources shipped, the jar would define every SDL
  # class a second time (R8: "Type org.libsdl.app... is defined multiple times").
  if [[ ! -d "${stage}/sdl3Java" && -d "${ladybird_dir}/Build/vcpkg-release/packages" ]]; then
    while IFS= read -r jar; do
      [[ -n "${jar}" ]] || continue
      mkdir -p "${stage}/sdl3Jar"
      # A prefix keeps jars of the same name from different packages apart.
      cp "${jar}" "${stage}/sdl3Jar/$(printf '%02d' "${index}")-$(basename "${jar}")"
      index=$((index + 1))
    done < <(find "${ladybird_dir}/Build/vcpkg-release/packages" -type f \
      \( -name 'SDL3.jar' -o -name 'SDL3-*.jar' \) ! -name '*-sources.jar' | LC_ALL=C sort)
  fi
  has_sdl3_java "${stage}" ||
    die "found neither SDL3 Java sources under ${ladybird_build}/generated/sdl3Java nor an SDL3 jar under ${ladybird_dir}/Build/vcpkg-release/packages"
}

package_artifact() {
  local platform="$1" source="$2" out_dir="$3"
  validate_platform "${platform}"
  [[ -n "${source}" && -n "${out_dir}" ]] || die "package needs a source and an output directory"
  [[ -d "${source}" ]] || die "${source} is not a directory"

  local fingerprint asset stage manifest_dir archive
  fingerprint="$(native_fingerprint)"
  asset="$(asset_name "${platform}" "${fingerprint}")"
  manifest_dir="$(mktemp -d)"
  TEMP_DIRS+=("${manifest_dir}")

  local root="${source}"
  if [[ "${platform}" == android-arm64-v8a ]]; then
    stage="$(mktemp -d)"
    TEMP_DIRS+=("${stage}")
    package_android_stage "${source}" "${stage}"
    root="${stage}"
  fi
  check_required_entries "${platform}" "${root}"

  cat >"${manifest_dir}/${MANIFEST_NAME}" <<EOF
{
  "platform": "${platform}",
  "fingerprint": "${fingerprint}",
  "ladybird_revision": "$(ladybird_revision)",
  "source_commit": "${GITHUB_SHA:-unknown}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  mkdir -p "${out_dir}"
  archive="${out_dir}/${asset}"
  # No AppleDouble (._*) files from macOS's tar.
  COPYFILE_DISABLE=1 tar -czf "${archive}" -C "${root}" --exclude "${STAMP_NAME}" . -C "${manifest_dir}" "${MANIFEST_NAME}"
  printf '%s  %s\n' "$(sha256_of_file "${archive}")" "${asset}" >"${archive}.sha256"
  log "packaged ${archive}"
  echo "${archive}"
}

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//' >&2
}

main() {
  local command="${1:-}"
  shift || true
  case "${command}" in
    mode) resolved_mode "${1:-}" ;;
    fingerprint) native_fingerprint ;;
    tag) release_tag "$(native_fingerprint)" ;;
    asset-name)
      [[ -n "${1:-}" ]] || die "asset-name needs a platform"
      validate_platform "$1"
      asset_name "$1" "$(native_fingerprint)"
      ;;
    fetch) fetch_artifact "${1:-}" "${2:-}" ;;
    package) package_artifact "${1:-}" "${2:-}" "${3:-}" ;;
    -h | --help | help | "") usage ;;
    *)
      usage
      die "unknown command '${command}'"
      ;;
  esac
}

main "$@"
