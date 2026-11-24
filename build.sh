#!/bin/bash
# Kullanım göstergesini derler ve ~/Applications içine kurar.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/Kullanim.app"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Kullanim.app/Contents/MacOS"
swiftc -O -swift-version 5 Sources/main.swift -o "$WORK/Kullanim.app/Contents/MacOS/Kullanim"
cp Info.plist "$WORK/Kullanim.app/Contents/Info.plist"
codesign --force --sign - "$WORK/Kullanim.app" 2>/dev/null
pkill -x Kullanim 2>/dev/null || true
mkdir -p "$HOME/Applications"; rm -rf "$APP"; mv "$WORK/Kullanim.app" "$APP"
open "$APP"
