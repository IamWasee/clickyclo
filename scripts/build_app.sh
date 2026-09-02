#!/usr/bin/env bash
#
# build_app.sh — compile ClickyClo and assemble a launchable .app bundle.
#
# SwiftPM emits a bare Mach-O executable, which cannot carry an Info.plist. macOS
# needs that plist for LSUIElement (no Dock tile) and, from Stage 3 onward, for
# the TCC usage strings that drive the Screen Recording and Microphone prompts.
#
# Usage:
#   ./scripts/build_app.sh            # release build, assemble bundle
#   ./scripts/build_app.sh --debug    # debug build
#   ./scripts/build_app.sh --run      # build, assemble, then launch
#
# Signing: ad-hoc by default. Export CODESIGN_IDENTITY="Developer ID Application: ..."
# to sign with a real identity, which keeps macOS privacy permissions granted to
# the app across rebuilds instead of re-prompting.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="release"
LAUNCH_AFTER_BUILD="false"

for arg in "$@"; do
  case "$arg" in
    --debug)   CONFIGURATION="debug" ;;
    --release) CONFIGURATION="release" ;;
    --run)     LAUNCH_AFTER_BUILD="true" ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: ClickyClo is a macOS application and can only be built on macOS." >&2
  exit 1
fi

APP_NAME="ClickyClo"
BUILD_DIR="${REPO_ROOT}/.build/${CONFIGURATION}"
BUNDLE_ROOT="${REPO_ROOT}/.build/bundle"
APP_BUNDLE="${BUNDLE_ROOT}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} (${CONFIGURATION})"
swift build --configuration "${CONFIGURATION}" --package-path "${REPO_ROOT}"

BINARY="${BUILD_DIR}/${APP_NAME}"
if [[ ! -x "${BINARY}" ]]; then
  echo "error: expected product not found at ${BINARY}" >&2
  exit 1
fi

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${REPO_ROOT}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Signing with identity: ${IDENTITY}"
codesign --force --sign "${IDENTITY}" --timestamp=none "${APP_BUNDLE}"
codesign --verify --verbose=2 "${APP_BUNDLE}"

echo "==> Built ${APP_BUNDLE}"

if [[ "${LAUNCH_AFTER_BUILD}" == "true" ]]; then
  echo "==> Launching ${APP_NAME}"
  # Terminate a previous instance so two overlays never stack.
  pkill -x "${APP_NAME}" 2>/dev/null || true
  open "${APP_BUNDLE}"
fi
