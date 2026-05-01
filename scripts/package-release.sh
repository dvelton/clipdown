#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
ZIP_PATH="$ROOT_DIR/dist/Clipdown.zip"
VERSIONED_ZIP_PATH="$ROOT_DIR/dist/Clipdown-$VERSION.zip"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/package-app.sh" >/dev/null

rm -f "$ZIP_PATH" "$VERSIONED_ZIP_PATH"
ditto -c -k --keepParent "$ROOT_DIR/dist/Clipdown.app" "$ZIP_PATH"
cp "$ZIP_PATH" "$VERSIONED_ZIP_PATH"

echo "Built $ZIP_PATH"
echo "Built $VERSIONED_ZIP_PATH"
