<p align="center">
  <img src="build/icon.png" alt="ExamsTrack icon" width="96" height="96">
</p>

<h1 align="center">ExamsTrack for Windows</h1>

<p align="center">
  The desktop version of ExamsTrack: exams, study plan, career and simulator, synced with the iPhone and iPad app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%2B-0078D4?style=flat-square" alt="Windows 10+">
  <img src="https://img.shields.io/badge/Electron-44-47848F?style=flat-square&logo=electron&logoColor=white" alt="Electron 44">
  <img src="https://img.shields.io/badge/JavaScript-no_framework-F7DF1E?style=flat-square&logo=javascript&logoColor=black" alt="JavaScript, no framework">
  <img src="https://img.shields.io/badge/License-MIT-2E8B57?style=flat-square" alt="MIT License">
</p>

The desktop app matches the iOS app as of November 2026. Like the iOS app, its interface is in Italian. Widgets, Live Activities, Shortcuts and Control Center controls are iOS-only.

## Download

Get the latest installer or portable `.exe` from [Releases](https://github.com/tommipisca/ExamsTrack/releases?q=desktop&expanded=true). The installer is not code-signed: if Windows SmartScreen warns you on first launch, click **More info → Run anyway**.

## Features

- "Today" view with the tasks of all exams: overdue, today, the next 7 days and later
- Exams with study tasks, sub-task checklists and quick add
- Timed study sessions with a Windows notification at the end
- Career: weighted average, CFU, graduation mark estimate and "what if" simulator
- Same "ink and highlighter" theme as the iOS app, with countdowns in Bahnschrift Condensed and exam names in Sitka
- Runs in the notification area (tray) when the window is closed

## Updates

The installed app checks GitHub for a new version at startup and every 6 hours. When it finds one, it downloads it in the background and installs it when you quit ExamsTrack. You can also install it right away from **Impostazioni → Aggiornamenti → Riavvia e aggiorna**, or from the tray menu (**Controlla aggiornamenti**). Automatic checks can be turned off in the same section. Your data in `%APPDATA%\ExamsTrack` is not touched.

The portable version cannot update itself: it shows a notification with a link to the new release.

Versions up to 1.1.0 have no update check, so version 1.2.0 must be installed manually once.

## Sync with iPhone and iPad

The desktop app reads and writes the same `ExamsTrack-sync.json` file as the iOS app, merged exam by exam.

1. Install iCloud for Windows, so that the iCloud Drive folder is available on the PC.
2. In ExamsTrack, open **Impostazioni → Sincronizzazione → Collega** and choose the same iCloud Drive folder used on iPhone and iPad.

Local data lives in `%APPDATA%\ExamsTrack\data` (`exams.json`, `deletions.json`), in the same format as the iOS app.

## Development

Requirements: [Node.js](https://nodejs.org) on Windows.

```powershell
cd desktop
npm install
npm start       # run the app
npm test        # tests for the shared logic in src/core
npm run dist    # NSIS installer + portable .exe in %LOCALAPPDATA%\ExamsTrack-build
```

### Publishing a release

1. Bump `version` in `package.json` (and `package-lock.json` with `npm install`), commit and push.
2. Run `npm run dist`.
3. Create a GitHub release tagged `desktop-v<version>` and attach `ExamsTrack-Setup-<version>.exe`, `ExamsTrack-portable-<version>.exe` and **`latest.yml`** from `%LOCALAPPDATA%\ExamsTrack-build`.

The installed app reads `latest.yml` from the latest release (`releases/latest/download/latest.yml`), so every desktop release must include it and must be the repository's latest release. Releases that aren't for the desktop app must be marked as pre-releases.

`npm run dist` writes outside the project folder on purpose. OneDrive locks files while electron-builder is running, which breaks the build when the project sits in a synced folder.

## Project structure

```
desktop/
├── src/
│   ├── core/         # Logic ported from ExamsCore (Swift): model, store, merge, sync, notifications
│   ├── renderer/     # UI: plain HTML, CSS and JavaScript, no framework
│   ├── main.cjs      # Electron main process: files, windows, tray, notifications
│   └── preload.cjs   # Bridge between the renderer and the main process
├── test/             # node:test suite for src/core
├── build/icon.png    # App icon (same as the iOS app)
└── package.json      # Scripts and electron-builder config
```

> [!IMPORTANT]
> `src/core` writes JSON byte for byte like Swift's `JSONEncoder`, so that merging converges on every device. Any change to the data format must be made both here and in `ExamsCore`, and stay compatible with existing files.

## Disclaimer

ExamsTrack is an independent personal project. It is not affiliated with, endorsed by or sponsored by Apple Inc. or Microsoft Corporation. Windows is a trademark of Microsoft Corporation. iPhone, iPad and iCloud are trademarks of Apple Inc. The app syncs through a folder that you choose, such as iCloud Drive, and does not use any Apple API. See the [main README](../README.md#disclaimer) for the full disclaimer.

## License

Distributed under the [MIT license](../LICENSE).
