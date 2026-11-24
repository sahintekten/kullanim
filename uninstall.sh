#!/bin/bash
# Removes Kullanım from this Mac.
set -uo pipefail
APP="$HOME/Applications/Kullanim.app"
[ -x "$APP/Contents/MacOS/Kullanim" ] && "$APP/Contents/MacOS/Kullanim" --login-off >/dev/null 2>&1
pkill -x Kullanim 2>/dev/null
rm -rf "$APP" "$HOME/Applications/Kullanim Chrome"
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/local.kullanim.json"
rm -f "$HOME/.claude/kullanim.json" "$HOME/.claude/kullanim-tarayici.log"
echo "Kullanım removed. In Chrome, remove the \"Kullanım göstergesi\" extension at chrome://extensions."
