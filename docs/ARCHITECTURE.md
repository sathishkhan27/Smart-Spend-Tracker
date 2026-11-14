# Architecture

Feature-first clean architecture (`lib/features/<feature>/{domain,data,presentation}`), Riverpod for DI/state, GoRouter for navigation.

```
SMS (native SmsBridge.kt) ─┐
Gmail API (OAuth)  ────────┼─▶ RawMessage ─▶ TransactionProcessor ─▶ DuplicateDetector ─▶ LocalStore outbox ─▶ Firestore
                           │      parse → validate → categorize → fingerprint      (sqflite, offline-safe)   (idempotent IDs)
                           └─ SyncService (progress stream, checkpoints, retry)                                 │
                                                                                         Cloud Function onTransactionWritten
                                                                                         → monthly_stats, counterparties, FCM
```

| Layer | Key files |
|---|---|
| Parsing engine | `transactions/domain/engines/transaction_parser.dart`, `bank_templates.dart` (configurable; extra templates loadable from `transaction_rules`) |
| Categorization | `categorization_engine.dart` — learned merchant mappings → type rules → keyword rules → P2P heuristic → Others (+review) |
| Dedupe | `duplicate_detector.dart` — deterministic IDs (ref-based) + scored matching (amount, direction, account, time window, counterparty) |
| Recurring | `upcoming/domain/recurring_detector.dart` — cadence + amount variance + confidence; suggestions need user confirmation |
| Totals | `dashboard/domain/period_aggregate.dart` — success-only, excludes failed/pending/internal transfers, refunds separate, no cross-currency sums |
| Sync | `sync/data/sync_service.dart`, `local_store.dart`, `background_sync.dart` |

## Firestore collections
`users`, `workspaces` (+`monthly_stats`), `workspace_members`, `workspace_invites`, `transactions` (+`private/{uid}`),
`transaction_rules`, `recurring_expenses`, `counterparties`, `categories`, `connected_accounts`, `sync_logs`, `notifications`.

Security model (`firebase/firestore.rules`): members of a workspace read its transactions; only the owner or a workspace admin edits/deletes;
any member may only *attach a source* to an existing canonical record; `private/{uid}` source details are owner-only; aggregates are server-written.

## Data-loading strategy
- Monthly / custom dashboards: date-scoped live query (cache-first, ≤2,500 docs).
- Yearly: server aggregates (`monthly_stats`) — no year-long download.
- History: cursor pagination (30/page) with one server-side filter + client refinement; `searchKeywords` array for prefix search.
