#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"

mkdir -p "$BUILD_DIR"

clang \
  -fobjc-arc \
  "$ROOT_DIR/src/ClipdownApp.m" \
  -o "$BUILD_DIR/Clipdown" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework JavaScriptCore

echo "$BUILD_DIR/Clipdown"
