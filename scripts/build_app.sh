#!/usr/bin/env bash
#
# build_app.sh — compile ClickyClo and assemble a launchable .app bundle.
#
# By default this compiles the sources directly with `swiftc` and does not use
# SwiftPM at all. ClickyClo has no external dependencies, so SwiftPM buys us
# nothing at build time — and a mismatched or partially-installed Command Line
# Tools ships a PackageDescription library that cannot link, which makes
# `swift build` fail before it ever reaches our code:
#
#   error: 'clickyclo': Invalid manifest
#   Undefined symbols: PackageDescription.Package.__allocating_init(...)
#
# `Package.swift` is still there for Xcode and for anyone with a healthy
# toolchain; pass --spm to use it.
#
# Usage:
#   ./scripts/build_app.sh            # release build, assemble bundle
#   ./scripts/build_app.sh --debug    # unoptimised build with debug symbols
#   ./scripts/build_app.sh --run      # build, assemble, then launch
#   ./scripts/build_app.sh --spm      # build via SwiftPM instead of swiftc
#
# Signing: ad-hoc by default. Export CODESIGN_IDENTITY="Developer ID Application: ..."
# to sign with a real identity, which keeps macOS privacy permissions granted to
# the app across rebuilds instead of re-prompting.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClickyClo"
BUNDLE_ID="com.clickyclo.companion"
DEPLOYMENT_TARGET="13.0"

CONFIGURATION="release"
LAUNCH_AFTER_BUILD="false"
USE_SWIFTPM="false"

for arg in "$@"; do
  case "$arg" in
    --debug)   CONFIGURATION="debug" ;;
    --release) CONFIGURATION="release" ;;
    --run)     LAUNCH_AFTER_BUILD="true" ;;
    --spm)     USE_SWIFTPM="true" ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: ClickyClo is a macOS application and can only be built on macOS." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install the Xcode Command Line Tools:" >&2
  echo "         xcode-select --install" >&2
  exit 1
fi

BUILD_ROOT="${REPO_ROOT}/.build/${CONFIGURATION}"
BUNDLE_ROOT="${REPO_ROOT}/.build/bundle"
APP_BUNDLE="${BUNDLE_ROOT}/${APP_NAME}.app"
BINARY="${BUILD_ROOT}/${APP_NAME}"

if [[ "${USE_SWIFTPM}" == "true" ]]; then
  echo "==> Building ${APP_NAME} via SwiftPM (${CONFIGURATION})"
  swift build --configuration "${CONFIGURATION}" --package-path "${REPO_ROOT}"
else
  SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
  HOST_ARCH="$(uname -m)"
  TARGET_TRIPLE="${HOST_ARCH}-apple-macosx${DEPLOYMENT_TARGET}"

  # Deterministic file order keeps diagnostics stable between runs. `main.swift`
  # is recognised as the entry point by name, not by position.
  SOURCES=()
  while IFS= read -r file; do
    SOURCES+=("$file")
  done < <(find "${REPO_ROOT}/Sources" -name '*.swift' | sort)

  if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "error: no Swift sources found under ${REPO_ROOT}/Sources" >&2
    exit 1
  fi

  if [[ "${CONFIGURATION}" == "release" ]]; then
    OPTIMISATION_FLAGS=(-O -whole-module-optimization)
  else
    OPTIMISATION_FLAGS=(-Onone -g)
  fi

  echo "==> Compiling ${#SOURCES[@]} source files with swiftc (${CONFIGURATION}, ${TARGET_TRIPLE})"
  mkdir -p "${BUILD_ROOT}"
  swiftc \
    -sdk "${SDK_PATH}" \
    -target "${TARGET_TRIPLE}" \
    -swift-version 5 \
    "${OPTIMISATION_FLAGS[@]}" \
    -module-name "${APP_NAME}" \
    -o "${BINARY}" \
    "${SOURCES[@]}"
fi

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

echo "==> Built ${APP_BUNDLE}  (bundle id ${BUNDLE_ID})"

if [[ "${LAUNCH_AFTER_BUILD}" == "true" ]]; then
  echo "==> Launching ${APP_NAME}"
  # Terminate a previous instance so two overlays never stack.
  pkill -x "${APP_NAME}" 2>/dev/null || true
  open "${APP_BUNDLE}"
  echo "    Quit with: pkill -x ${APP_NAME}"
fi
