#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PACKAGE_ROOT}/third_party/ladybird.version"
LADYBIRD_DIR="${PACKAGE_ROOT}/third_party/ladybird"

if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "Missing Ladybird version file: ${VERSION_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${VERSION_FILE}"

: "${LADYBIRD_REPOSITORY:?Missing LADYBIRD_REPOSITORY in ${VERSION_FILE}}"
: "${LADYBIRD_REF:?Missing LADYBIRD_REF in ${VERSION_FILE}}"
: "${LADYBIRD_REVISION:?Missing LADYBIRD_REVISION in ${VERSION_FILE}}"

current_status=""

mkdir -p "${PACKAGE_ROOT}/third_party"

# If the directory exists but has no .git of its own it is either an empty
# placeholder inside a parent git repo or was never cloned.  Remove it so the
# clone step below can proceed cleanly.
if [[ -d "${LADYBIRD_DIR}" && ! -e "${LADYBIRD_DIR}/.git" ]]; then
  rmdir "${LADYBIRD_DIR}" 2>/dev/null || {
    echo "Ladybird directory exists but is not a git checkout and is not empty: ${LADYBIRD_DIR}" >&2
    echo "Remove it and rerun the build so libbird can clone a fresh checkout." >&2
    exit 1
  }
fi

if [[ -d "${LADYBIRD_DIR}" ]]; then
  if ! git -C "${LADYBIRD_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Existing Ladybird directory is not a git checkout: ${LADYBIRD_DIR}" >&2
    echo "Remove it and rerun the build so libbird can clone a fresh checkout." >&2
    exit 1
  fi

  current_revision="$(git -C "${LADYBIRD_DIR}" rev-parse HEAD)"
  current_status="$(git -C "${LADYBIRD_DIR}" status --porcelain --untracked-files=no)"
  if [[ -n "${current_status}" && "${current_revision}" != "${LADYBIRD_REVISION}" ]]; then
    echo "Ladybird checkout has local changes and cannot be moved to ${LADYBIRD_REVISION}." >&2
    echo "Commit, stash, or remove ${LADYBIRD_DIR} before changing the pinned revision." >&2
    exit 1
  fi
fi

if [[ ! -d "${LADYBIRD_DIR}" ]]; then
  git clone --filter=blob:none --branch "${LADYBIRD_REF}" "${LADYBIRD_REPOSITORY}" "${LADYBIRD_DIR}"
else
  current_remote="$(git -C "${LADYBIRD_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ "${current_remote}" != "${LADYBIRD_REPOSITORY}" ]]; then
    git -C "${LADYBIRD_DIR}" remote set-url origin "${LADYBIRD_REPOSITORY}"
  fi

  git -C "${LADYBIRD_DIR}" fetch --force --prune origin "${LADYBIRD_REF}"
fi

if ! git -C "${LADYBIRD_DIR}" cat-file -e "${LADYBIRD_REVISION}^{commit}" 2>/dev/null; then
  git -C "${LADYBIRD_DIR}" fetch --force --prune --tags origin
fi

current_revision="$(git -C "${LADYBIRD_DIR}" rev-parse HEAD)"
needs_checkout=0

if [[ "${current_revision}" != "${LADYBIRD_REVISION}" ]]; then
  needs_checkout=1
fi

# Some interrupted/partial checkouts can leave only .git metadata present.
# Ensure expected source files are materialized before native builds continue.
if [[ ! -f "${LADYBIRD_DIR}/Meta/ladybird.py" ]]; then
  if [[ -n "${current_status}" ]]; then
    echo "Ladybird checkout is missing expected files and has local changes: ${LADYBIRD_DIR}" >&2
    echo "Clean or recreate the checkout before retrying the build." >&2
    exit 1
  fi
  needs_checkout=1
fi

if [[ "${needs_checkout}" -eq 1 ]]; then
  git -C "${LADYBIRD_DIR}" checkout --detach "${LADYBIRD_REVISION}"
fi
