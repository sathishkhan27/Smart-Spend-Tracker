# Platform & policy limitations

## SMS
- **Android only.** iOS gives third-party apps no access to the SMS inbox; on iOS the app relies on email.
- `READ_SMS` / `RECEIVE_SMS` are **restricted permissions on Google Play**. Apps must be approved via the
  *Permissions Declaration Form*; finance/expense trackers are not automatically eligible. Options:
  1. Distribute outside Play (enterprise / direct APK) with SMS enabled, or
  2. Ship a Play build with SMS removed (delete the two permissions from `AndroidManifest.xml`) and rely on email,
  3. Or use the Android *SMS Retriever / User Consent API* for one-off messages (not suitable for inbox scans).
- Permission is requested only after the in-app consent screen; consent is recorded in `users/{uid}.consents` with a timestamp and policy version.
- Messages are parsed on-device. Only extracted fields are uploaded; a ≤200-char masked excerpt is stored in an owner-only sub-document.

## Gmail
- `gmail.readonly` is a restricted scope; production use needs Google OAuth verification and an annual security assessment.
- Tokens are held by Google Play Services / iOS keychain via `google_sign_in`; the app never stores passwords or refresh tokens.
- Background Gmail sync works while the user's grant is valid; if Google requires re-consent the source shows **Re-authorization required**.
- Outlook/Microsoft 365 (Microsoft Graph) is stubbed in the UI as "coming soon".

## Background sync
- Android WorkManager runs at most every ~15–30 min and may be deferred by Doze.
- iOS background fetch timing is OS-controlled and not guaranteed.
