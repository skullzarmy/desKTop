#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Building and Launching desKTop locally ==="
"$DIR/scripts/bundle.sh"

echo "Opening desKTop.app..."
open "$DIR/build/desKTop.app"

echo "✓ desKTop is now running in your macOS Menu Bar and Desktop!"
