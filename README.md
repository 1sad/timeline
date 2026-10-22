# Timeline

Timeline is a finite eight-day planner for tracking events during the day, built with Flutter for Windows and Android.

![Timeline screenshot](docs/screenshot.png)

## Features

- Eight-day canvas with zoom from one hour to the full range
- Events and longer zones arranged in category tracks
- Drag, resize, create, edit, and undo directly on the timeline
- Templates, recurring events, alarms, and a lock mode
- JSON import and export for local backups and moving data
- Windows tray support and Android notifications

## Requirements

- Flutter with Dart 3.13.5 or newer
- Windows 10 or 11 with the desktop toolchain for Windows builds
- Android SDK and Android 8.0 (API 26) or newer for Android builds

## Build and run

Windows:

```sh
flutter pub get
flutter run -d windows
flutter build windows --release
```

Android:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
flutter build apk --release
```

## Data

Timeline stores its data locally with `shared_preferences`. Use the in-app JSON export and import to back up data or move it between devices. There is no cloud sync.

## Development

Built with Flutter. Developed with assistance from OpenCode using DeepSeek V4.1 Flash Free.

## License

GNU General Public License v3.0 only (GPL-3.0-only). See [LICENSE](LICENSE).

Copyright (C) 2026 1sad.
