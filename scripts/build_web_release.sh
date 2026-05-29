#!/usr/bin/env bash
set -euo pipefail

FLUTTER_BIN="${FLUTTER_BIN:-flutter/bin/flutter}"
if [[ ! -x "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="flutter"
fi

ENABLE_HARMONY_CHAT="${ENABLE_HARMONY_CHAT:-true}"
# --no-web-resources-cdn keeps CanvasKit served from our own origin
# (build/web/canvaskit, cached immutable by vercel.json) instead of
# gstatic.com, removing a third-party round-trip on first load.
"$FLUTTER_BIN" build web --release --no-web-resources-cdn --no-tree-shake-icons --dart-define=ENABLE_HARMONY_CHAT="$ENABLE_HARMONY_CHAT"

export ICON_ASSET_VERSION="${ICON_ASSET_VERSION:-icons-20260521}"
MAIN_JS="build/web/main.dart.js"
FONT_MANIFEST="build/web/assets/FontManifest.json"

if [[ -f "$MAIN_JS" ]]; then
  perl -0pi -e 's/FontManifest\.json/FontManifest.json?v=$ENV{ICON_ASSET_VERSION}/g' "$MAIN_JS"
fi

if [[ -f "$FONT_MANIFEST" ]]; then
  perl -0pi -e 's/fonts\/MaterialIcons-Regular\.otf/fonts\/MaterialIcons-Regular.otf?v=$ENV{ICON_ASSET_VERSION}/g' "$FONT_MANIFEST"
fi
