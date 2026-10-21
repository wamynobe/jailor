#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Jailor.app"
DEPLOYMENT="${DEPLOYMENT:-14.0}"

# Universal by default: native on Apple Silicon and Intel.
# Override with e.g. JAILOR_ARCHS="arm64-apple-macosx14.0" for a single-arch build.
if [ -n "${JAILOR_ARCHS:-}" ]; then
  read -r -a ARCHS <<< "$JAILOR_ARCHS"
else
  ARCHS=("arm64-apple-macosx${DEPLOYMENT}" "x86_64-apple-macosx${DEPLOYMENT}")
fi

if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  echo "→ Creating app icon…"
  /usr/bin/swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources"
fi

echo "→ Build ($CONFIG, ${ARCHS[*]})…"
BINARIES=()
for ARCH in "${ARCHS[@]}"; do
  swift build -c "$CONFIG" --triple "$ARCH"
  BIN_DIR="$(swift build -c "$CONFIG" --triple "$ARCH" --show-bin-path)"
  BIN="$BIN_DIR/Jailor"
  if [ ! -x "$BIN" ]; then
    echo "Binary not found $BIN" >&2
    exit 1
  fi
  BINARIES+=("$BIN")
done

echo "Bundling app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${#BINARIES[@]}" -eq 1 ]; then
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/Jailor"
else
  /usr/bin/lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Jailor"
fi

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

/usr/bin/xattr -cr "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

echo "Holala your Jailor is ready at $APP"
