<p align="center">
  <img src="AppIcon.png" alt="ExamsTrack icon" width="128" height="128">
</p>

<h1 align="center">ExamsTrack</h1>

<p align="center">
  An iOS and iPadOS app for university students to plan exams, track study tasks and keep an eye on their grade average and expected graduation mark.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17%2B-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-UI-1F4E79?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/WidgetKit-Live_Activities-6C63FF?style=flat-square" alt="WidgetKit and Live Activities">
  <img src="https://img.shields.io/badge/Built_with-xtool-0EA5A4?style=flat-square" alt="Built with xtool">
  <img src="https://img.shields.io/badge/License-MIT-2E8B57?style=flat-square" alt="MIT License">
</p>

ExamsTrack is built around the Italian university system (grades out of 30 with *lode*, CFU credits, graduation mark out of 110), and its interface is in Italian. It is written entirely in SwiftUI and developed on Linux (Ubuntu on WSL) with [xtool](https://github.com/xtool-org/xtool), without Xcode or a Mac.

## Features

**Exams and study tasks**
- Exams with date, start time, CFU, notes and a highlighter colour, split between BSc and MSc degrees
- Study tasks with due dates and sub-task checklists, shown on a timeline next to the exam countdown
- Automatic study plan that spreads topics until the exam day, with a final review
- "Today" view with overdue, today's and upcoming tasks across all exams; on iPad, a two-column board where tasks can be dragged to another day
- Swipe and context-menu actions: mark as done, move to tomorrow, start a study session, edit, delete
- Search across exam names, notes and task titles (case- and accent-insensitive)

**Career and simulation**
- Weighted average, earned CFU and an average trend chart
- Estimated graduation mark with min/max range, *lode* threshold and master's thesis type
- "What if" simulator: hypothetical grades for upcoming exams and their effect on average and final mark

**System integration**
- Home Screen and Lock Screen widgets: next exam, today's tasks, average and simulation; tasks can be checked off directly from the widget
- Live Activities on the Lock Screen and Dynamic Island for exam day and for timed study sessions
- Control Center controls and Shortcuts actions ("What should I study today?", complete the next task, start a session)
- Notifications for exam reminders, daily task summaries and the end of a study session (with "Mark done" and "Pause" actions)

**Data**
- Local JSON storage shared between app and widgets through an App Group
- Sync between devices via a file in a user-chosen folder (e.g. iCloud Drive), merged exam by exam
- Automatic daily backups plus manual export and import

## Tech stack

<p align="center">
  <a href="https://skillicons.dev">
    <img src="https://skillicons.dev/icons?i=swift,apple,linux,git" alt="Swift, Apple, Linux and Git">
  </a>
</p>

- [Swift 6](https://www.swift.org) + [SwiftUI](https://developer.apple.com/xcode/swiftui/), with no storyboards or `.xcodeproj`
- [WidgetKit](https://developer.apple.com/widgets/), [ActivityKit](https://developer.apple.com/documentation/activitykit) and [App Intents](https://developer.apple.com/documentation/appintents) for widgets, Live Activities, controls and Shortcuts
- [Swift Charts](https://developer.apple.com/documentation/charts) for the average trend
- [xtool](https://github.com/xtool-org/xtool) to build, sign and install on a device from Linux
- Swift Package Manager, with the business logic in a separate, fully tested `ExamsCore` package

## Getting started

Requirements: [xtool](https://github.com/xtool-org/xtool) set up with an Apple ID (a free account works) and an iPhone or iPad connected via USB.

```bash
# 1. Clone the repository
git clone https://github.com/tommipisca/ExamsTrack.git
cd ExamsTrack

# 2. Build
xtool dev build

# 3. Install the built app on the connected device
xtool install --usb xtool/ExamsTrack.app
```

> [!NOTE]
> xtool does not generate the App Intents metadata (`Metadata.appintents`) that Xcode normally produces. Without it the app still runs, but checking off tasks from widgets and Control Center doesn't work, and Shortcuts actions may be missing. In my setup a small local script runs after `xtool dev build`, extracts the metadata into the app and widget bundles, and then installs the app.

With a free Apple account the installed app expires after 7 days and must be reinstalled; ExamsTrack shows the expiration date in its settings. The free account also limits the number of App IDs, so reuse the bundle IDs in `xtool.yml` (or change them to your own).

### Running the tests

The logic in `ExamsCore` has no UI dependencies, so its test suite runs on Linux as well:

```bash
cd ExamsCore
swift test
```

## Project structure

```
ExamsTrack/
├── Sources/
│   ├── ExamsTrack/          # SwiftUI app: tabs, forms, sync, notifications, Shortcuts
│   └── ExamsTrackWidget/    # Widgets, Live Activities and Control Center controls
├── ExamsCore/               # Shared logic: models, store, grade math, sync merge, planning
│   ├── Sources/ExamsCore/
│   └── Tests/ExamsCoreTests/
├── Package.swift            # SwiftPM manifest (app + widget targets)
├── xtool.yml                # xtool config: bundle IDs, plists, entitlements, icon
├── App-Info.plist           # App Info.plist
├── Widget-Info.plist        # Widget extension Info.plist
├── App.entitlements         # App Group shared by app and widget
└── AppIcon.png              # 1024×1024 app icon
```

## License

Distributed under the [MIT license](LICENSE).
