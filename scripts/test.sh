#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/test"

mkdir -p "$BUILD_DIR"

clang \
  -fobjc-arc \
  "$ROOT_DIR/Tests/ClipdownConverterTests.m" \
  -o "$BUILD_DIR/ClipdownCoreTests" \
  -framework Foundation \
  -framework JavaScriptCore

"$BUILD_DIR/ClipdownCoreTests" "$ROOT_DIR/Resources/clipdown-converter.js"
