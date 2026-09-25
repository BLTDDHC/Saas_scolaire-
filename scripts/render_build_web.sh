#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="${RENDER_FLUTTER_DIR:-$PWD/.render/flutter}"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR"
  mkdir -p "$(dirname "$FLUTTER_DIR")"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter config --enable-web
flutter pub get

if [ -z "${API_BASE_URL:-}" ]; then
  echo "API_BASE_URL must be defined for the hosted Flutter build." >&2
  exit 1
fi

flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
