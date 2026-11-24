#!/bin/bash
# Builds Kullanım on this Mac, installs it to ~/Applications and connects it to Google Chrome.
set -euo pipefail

REPO="https://github.com/sahintekten/kullanim"
APP="$HOME/Applications/Kullanim.app"
EXT="$HOME/Applications/Kullanim Chrome"
EXT_ID="acjapefffdijkmdaccfimfcponjncmlc"
HOSTS="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Kullanım is built on your Mac, which needs Apple's Command Line Tools."
  echo "Starting their installer; run this command again when it has finished."
  xcode-select --install || true
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if [ ! -f "$SRC/Sources/main.swift" ]; then
  # Started with "curl ... | bash": download the source first.
  echo "Downloading Kullanım..."
  mkdir "$WORK/src"
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$WORK/src" --strip-components=1
  SRC="$WORK/src"
fi

echo "Building (the first build can take a minute)..."
BUNDLE="$WORK/Kullanim.app"
mkdir -p "$BUNDLE/Contents/MacOS"
swiftc -O -swift-version 5 "$SRC/Sources/main.swift" -o "$BUNDLE/Contents/MacOS/Kullanim"
cp "$SRC/Info.plist" "$BUNDLE/Contents/Info.plist"
codesign --force --sign - "$BUNDLE" 2>/dev/null

pkill -x Kullanim 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mv "$BUNDLE" "$APP"

# Chrome extension folder (loaded once by hand: Chrome does not let scripts install extensions).
rm -rf "$EXT"
mkdir -p "$EXT"
cp "$SRC/chrome/manifest.json" "$SRC/chrome/background.js" "$EXT/"

# Lets the extension hand the percentages to the menu bar app (Chrome "native messaging").
mkdir -p "$HOSTS"
cat > "$HOSTS/local.kullanim.json" <<JSON
{
  "name": "local.kullanim",
  "description": "Kullanım: writes the claude.ai plan usage to the menu bar",
  "path": "$APP/Contents/MacOS/Kullanim",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
JSON

"$APP/Contents/MacOS/Kullanim" --login-on >/dev/null 2>&1 || true
open "$APP"

echo
echo "Done. The ring with a percentage is now in your menu bar."
echo
echo "One last step in Google Chrome (once):"
echo "  1. Go to chrome://extensions"
echo "  2. Turn on \"Developer mode\" (top right)"
echo "  3. Click \"Load unpacked\" and choose this folder:"
echo "     $EXT"
echo
echo "Stay signed in to claude.ai in Chrome; the reading refreshes every 3 minutes."
open -R "$EXT" 2>/dev/null || true
