# Smart Spend Tracker

Smart Spend Tracker is a Flutter-based mobile app for tracking personal and shared expenses by automatically extracting transaction data from SMS and email alerts, categorizing spending, and presenting insights in a clear dashboard.

It is designed for Android and iOS, with Firebase-powered sync, workspace sharing, and recurring payment monitoring.

## Features

- Automatic transaction extraction from bank SMS and Gmail alerts
- Smart categorization of expenses and income
- Deduplication across multiple sources
- Shared workspaces for families or teams
- Recurring payment detection and reminders
- Monthly, yearly, and custom financial insights
- PDF and Excel export support
- Offline queueing and background synchronization
- Light and dark theme support

## Sample Screenshot

<img width="540" height="1200" alt="WhatsApp Image 2026-11-14 at 11 24 53" src="https://github.com/user-attachments/assets/0cd98809-7ae5-45b2-9caa-749385d3bc16" />


*Sample app dashboard. Save the screenshot you shared as `docs/assets/screenshots/dashboard.png` in the repository to display it here.*

## Tech Stack

- Flutter / Dart
- Firebase Auth, Firestore, Cloud Functions, Cloud Messaging
- Google APIs for Gmail integration
- Android and iOS support

## Repository Structure

- `lib/` — Flutter application source code
- `docs/` — project setup, architecture, and platform notes
- `firebase/` — Firebase configuration, rules, indexes, and functions
- `android/` and `ios/` — platform-specific app configuration
- `test/` — unit and widget tests

## Quick Start

### Prerequisites

- Flutter 3.35+
- Dart 3.9+
- Node.js 20+
- Firebase CLI
- Android Studio / Xcode

### Install dependencies

```bash
flutter pub get
```

### Firebase setup

```bash
firebase login
flutterfire configure --project=smart-spend-27d7c --platforms=android,ios \
  --android-package-name=com.smartspend.smart_spend_tracker --ios-bundle-id=com.smartspend.smartSpendTracker
```

### Run the app

```bash
flutter run
```

### Run tests

```bash
flutter test
```

## Documentation

- [docs/SETUP.md](docs/SETUP.md) — setup and deployment instructions
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture overview
- [docs/PLATFORM_LIMITATIONS.md](docs/PLATFORM_LIMITATIONS.md) — platform and policy constraints

## Firebase Deployment

```bash
cd firebase/functions && npm install && cd ../..
firebase deploy --only firestore:rules,firestore:indexes,functions
```

## Notes

This project uses Firebase for shared data sync, role-based workspaces, and scheduled reminders. For Gmail-based parsing, configure the Google OAuth and Gmail API according to the setup guide.

## License

See the repository's license file for applicable terms.
