# Smart Spend Tracker — Setup & Deployment

Firebase project: **`smart-spend-27d7c`** (already set in `.firebaserc`).

## 1. Prerequisites
- Flutter 3.35+ (Dart 3.9+), Android Studio / Xcode
- Node.js 20 and the Firebase CLI: `npm i -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

## 2. Firebase console (one-time)
In https://console.firebase.google.com/project/smart-spend-27d7c :
1. **Authentication → Sign-in method** → enable **Email/Password**.
2. **Firestore Database** → create database (production mode, region `asia-south1`).
3. **Upgrade to Blaze plan** (required for Cloud Functions & scheduled reminders).
4. **App Check** → register Android (Play Integrity) and iOS (DeviceCheck/App Attest).
   For debug builds, add the debug token printed in logcat/Xcode console.
5. **Cloud Messaging** → for iOS upload an APNs auth key.

## 3. Connect the app to Firebase
```bash
firebase login
flutterfire configure --project=smart-spend-27d7c --platforms=android,ios \
  --android-package-name=com.smartspend.smart_spend_tracker --ios-bundle-id=com.smartspend.smartSpendTracker
```
This overwrites `lib/firebase_options.dart`. Add this getter to the generated class so
bootstrap and background sync can use it:
```dart
static FirebaseOptions? get currentPlatformOrNull => currentPlatform;
```
(Alternatively keep the provided file and pass values with `--dart-define=FIREBASE_API_KEY=… FIREBASE_PROJECT_ID=smart-spend-27d7c FIREBASE_ANDROID_APP_ID=… FIREBASE_MESSAGING_SENDER_ID=…`.)

## 4. Deploy rules, indexes and functions
```bash
cd firebase/functions && npm install && cd ../..
firebase deploy --only firestore:rules,firestore:indexes,functions
```
Functions deployed (region `asia-south1`):
| Function | Purpose |
|---|---|
| `onTransactionWritten` | Incremental monthly aggregates, counterparty directory, workspace-activity / uncategorized / unusual-spend notifications, private-doc cleanup |
| `joinWorkspace` | Redeems invite codes (clients can't add themselves) |
| `removeWorkspaceMember` | Admin-only member removal |
| `deleteMyData` | Data-deletion request: removes user's transactions, sources, logs, account |
| `dailyReminders` | 09:00 IST FCM reminders for EMI, rent, bills, card payments |

## 5. Gmail (OAuth 2.0)
1. Google Cloud Console (same project) → **APIs & Services → Enable Gmail API**.
2. **OAuth consent screen**: add scope `https://www.googleapis.com/auth/gmail.readonly`, add test users.
   `gmail.readonly` is a *restricted* scope — public release requires Google verification + a CASA security assessment.
3. **Credentials**: create OAuth clients
   - *Android* (package `com.smartspend.smart_spend_tracker` + your SHA-1: `cd android && ./gradlew signingReport`)
   - *Web application* → its client ID is the **server client ID**
   - *iOS* (bundle ID) → add its reversed client ID as a URL scheme in `ios/Runner/Info.plist`
4. Run with:
```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com \
            --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com
```

## 6. Run & test
```bash
flutter pub get
flutter test                       # 34 unit + widget tests (parser, categorizer, dedupe, recurring, calculator)
(cd firebase/functions && npm test)
flutter run                        # Android device recommended (SMS)
```
Local emulators: `firebase emulators:start`.

## 7. Release
- Android: configure a release keystore in `android/app/build.gradle.kts`, then `flutter build appbundle`.
- iOS: set signing team, enable *Background fetch* & *Push Notifications* capabilities, `flutter build ipa`.
- Switch App Check to production providers (automatic in release builds).

See `PLATFORM_LIMITATIONS.md` for SMS/Play-policy notes and `ARCHITECTURE.md` for the design.
