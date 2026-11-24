# Kullanım

A small menu bar app for macOS that always shows how much of your Claude plan you have used this week.

![Menu bar and panel](docs/preview.png)

The ring and the number show the weekly limit for all models. Click it to see every limit (for example a per-model weekly limit) with its reset time. The ring turns orange at 70% and red at 90%. It fades when the last reading is more than 3 hours old.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sahintekten/kullanim/main/install.sh | bash
```

No GitHub account is needed. The app is built on your Mac, so it needs Apple's Command Line Tools; if they are missing, the installer starts their setup and you run the command again afterwards. Requires macOS 13 or later.

A window opens: sign in to claude.ai there once (email code works; Google blocks its sign-in inside app windows, so use "Continue with email" if your account is a Google one). From then on the reading refreshes every 3 minutes, whichever browser you use. You can open the window again any time: click the ring > **Connect to claude.ai…**

### Chrome instead of signing in

If you use Chrome, you can skip the sign-in window and let a small extension read the usage from the claude.ai session you already have in Chrome:

1. Go to `chrome://extensions`
2. Turn on **Developer mode** (top right)
3. Click **Load unpacked** and choose the folder `~/Applications/Kullanim Chrome`

## How it works

- The app (or the Chrome extension) asks claude.ai for the same usage figures its own usage page shows, with your signed-in session.
- The sign-in window is a plain claude.ai page inside the app. Your session is kept only on your Mac, in the app's own web storage, and is only ever sent to claude.ai. **Disconnect claude.ai** in the menu deletes it.
- The Chrome extension hands only the percentages and reset times to the app through Chrome's native messaging; your login never leaves the browser.
- The reading is written to `~/.claude/kullanim.json` and the menu bar is redrawn from it. Nothing is sent anywhere else.

The usage data claude.ai serves is not a documented API, so a change on their side can break the reading until this app is updated.

### Optional: Claude Code desktop

If you use Claude Code, the `mod` folder in this repository is a Claude Code mod that writes the same file from inside your sessions (it also works when Chrome is closed). To load it in every new session, add this to `~/.claude/settings.json`, pointing at where you keep the folder:

```json
"env": { "CLAUDE_CODE_PLUGIN_DIRS": "/path/to/kullanim/mod" }
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sahintekten/kullanim/main/uninstall.sh | bash
```

Then remove the "Kullanım göstergesi" extension at `chrome://extensions`.

## Türkçe

Claude planının bu haftaki kullanımını menü çubuğunda sürekli gösteren küçük bir Mac uygulaması. Halka ve rakam tüm modellerin haftalık sınırıdır; tıklayınca model bazlı sınırlar ve sıfırlanma zamanları da görünür.

Kurmak için Terminal'e yapıştır:

```bash
curl -fsSL https://raw.githubusercontent.com/sahintekten/kullanim/main/install.sh | bash
```

Kurulumdan sonra açılan pencerede claude.ai'ye bir kez giriş yap (Google hesabıysa "Continue with email" ile e-postana gelen kodla gir). Okuma bundan sonra hangi tarayıcıyı kullanırsan kullan 3 dakikada bir yenilenir. Oturum yalnız bu Mac'te, uygulamanın içinde durur; menüdeki **claude.ai bağlantısını kes** onu siler. Chrome kullanıyorsan giriş yerine eklentiyi de kullanabilirsin (yukarıda).

## License

[MIT](LICENSE)
