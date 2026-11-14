enum SyncStage {
  idle('Ready'),
  connecting('Connecting to financial data sources...'),
  scanningSms('Scanning authorized SMS messages...'),
  fetchingEmails('Fetching bank transaction emails...'),
  identifying('Identifying financial transactions...'),
  extracting('Extracting transaction details...'),
  categorizing('Categorizing expenses...'),
  counterparties('Identifying merchants and counterparties...'),
  deduplicating('Checking duplicate transactions...'),
  synchronizing('Synchronizing data with Firebase...'),
  generating('Generating your financial dashboard...'),
  completed('Your dashboard is ready'),
  failed('Sync could not complete');

  const SyncStage(this.message);
  final String message;
}

enum SourceSyncStatus { idle, running, done, skipped, failed }

class SourceState {
  const SourceState(this.status, {this.error, this.detail});
  final SourceSyncStatus status;
  final String? error;
  final String? detail;
}

class SyncProgress {
  const SyncProgress({
    this.stage = SyncStage.idle,
    this.smsScanned = 0,
    this.smsTotal,
    this.emailsScanned = 0,
    this.emailsTotal,
    this.identified = 0,
    this.categorized = 0,
    this.synced = 0,
    this.duplicates = 0,
    this.needsReview = 0,
    this.queued = 0,
    this.sources = const {},
    this.startedAt,
    this.finishedAt,
  });

  final SyncStage stage;
  final int smsScanned;
  final int? smsTotal;
  final int emailsScanned;
  final int? emailsTotal;
  final int identified;
  final int categorized;
  final int synced;
  final int duplicates;
  final int needsReview;

  /// Records waiting in the offline outbox.
  final int queued;
  final Map<String, SourceState> sources;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isRunning => stage != SyncStage.idle && stage != SyncStage.completed && stage != SyncStage.failed;
  bool get isComplete => stage == SyncStage.completed;
  bool get hasFailures => sources.values.any((s) => s.status == SourceSyncStatus.failed);

  /// Real progress in 0..1, or null when the amount of work is unknown
  /// (the UI then shows an indeterminate indicator — never a fake number).
  double? get fraction {
    switch (stage) {
      case SyncStage.completed:
        return 1;
      case SyncStage.idle || SyncStage.connecting || SyncStage.failed:
        return null;
      default:
        break;
    }
    final smsKnown = smsTotal != null || !(sources['sms']?.status == SourceSyncStatus.running);
    final emailKnown = emailsTotal != null || !(sources['gmail']?.status == SourceSyncStatus.running);
    if (!smsKnown || !emailKnown) return null;
    final total = (smsTotal ?? 0) + (emailsTotal ?? 0);
    if (total == 0) return stage.index >= SyncStage.synchronizing.index ? 0.9 : null;
    final scanned = (smsScanned + emailsScanned).clamp(0, total);
    final scan = scanned / total * 0.85;
    return switch (stage) {
      SyncStage.synchronizing => 0.85 + 0.1 * (identified == 0 ? 1 : (synced / identified).clamp(0, 1)),
      SyncStage.generating => 0.97,
      _ => scan,
    };
  }

  SyncProgress copyWith({
    SyncStage? stage,
    int? smsScanned,
    int? smsTotal,
    int? emailsScanned,
    int? emailsTotal,
    int? identified,
    int? categorized,
    int? synced,
    int? duplicates,
    int? needsReview,
    int? queued,
    Map<String, SourceState>? sources,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) =>
      SyncProgress(
        stage: stage ?? this.stage,
        smsScanned: smsScanned ?? this.smsScanned,
        smsTotal: smsTotal ?? this.smsTotal,
        emailsScanned: emailsScanned ?? this.emailsScanned,
        emailsTotal: emailsTotal ?? this.emailsTotal,
        identified: identified ?? this.identified,
        categorized: categorized ?? this.categorized,
        synced: synced ?? this.synced,
        duplicates: duplicates ?? this.duplicates,
        needsReview: needsReview ?? this.needsReview,
        queued: queued ?? this.queued,
        sources: sources ?? this.sources,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  SyncProgress withSource(String key, SourceState s) => copyWith(sources: {...sources, key: s});
}
