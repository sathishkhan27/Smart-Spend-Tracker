# Smart Spend Tracker

Automatic, shared expense tracking for Flutter (Android & iOS). Transactions are extracted from authorized bank SMS and Gmail alerts,
categorized on-device, de-duplicated across sources and synced to a shared Firebase workspace with a premium dashboard.

**Highlights:** rule-based SMS/email parser (20+ Indian banks, UPI apps, wallets) · learning categorizer · SMS↔email dedupe ·
recurring-payment detection & reminders · monthly/yearly/custom insights · PDF/Excel export · multi-user workspaces with role-based rules ·
offline outbox & background sync · light/dark themes.

- Setup & deployment: [docs/SETUP.md](docs/SETUP.md)
- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Platform/policy limits: [docs/PLATFORM_LIMITATIONS.md](docs/PLATFORM_LIMITATIONS.md)

```bash
flutter pub get && flutter test
flutterfire configure --project=smart-spend-27d7c
firebase deploy --only firestore,functions
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
```
