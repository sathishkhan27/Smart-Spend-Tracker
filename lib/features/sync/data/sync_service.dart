import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/app_clock.dart';
import '../../transactions/data/rules_repository.dart';
import '../../transactions/data/transaction_mapper.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/engines/bank_templates.dart';
import '../../transactions/domain/engines/categorization_engine.dart';
import '../../transactions/domain/engines/duplicate_detector.dart';
import '../../transactions/domain/engines/raw_message.dart';
import '../../transactions/domain/engines/transaction_parser.dart';
import '../../transactions/domain/engines/transaction_processor.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_enums.dart';
import '../../cards/data/credit_card_repository.dart';
import '../../cards/domain/card_sms_parser.dart';
import '../../cards/domain/credit_card.dart';
import '../../upcoming/data/recurring_repository.dart';
import '../../upcoming/domain/due_payment_matcher.dart';
import '../../upcoming/domain/due_reminder_parser.dart';
import '../../upcoming/domain/recurring_detector.dart';
import '../../upcoming/domain/recurring_expense.dart';
import '../domain/sync_progress.dart';
import 'connected_accounts_repository.dart';
import 'gmail_source.dart';
import 'local_store.dart';
import 'sms_source.dart';

class SyncRequest {
  const SyncRequest({
    required this.ctx,
    this.initial = false,
    this.includeSms = true,
    this.includeGmail = true,
  });
  final ProcessingContext ctx;
  final bool initial;
  final bool includeSms;
  final bool includeGmail;
}

class SyncResult {
  const SyncResult({required this.newTransactions, required this.progress});
  final List<FinancialTransaction> newTransactions;
  final SyncProgress progress;
}

/// Orchestrates: source read → process → dedupe → local outbox → Firestore.
///
/// Guarantees:
/// * incremental – per-source checkpoints, processed-message ledger
/// * restartable – checkpoints advance only after a page is queued locally,
///   so an interruption never loses or double-counts records
/// * idempotent – deterministic document IDs and merge semantics
/// * offline-safe – records wait in the outbox until Firestore accepts them
class SyncService {
  SyncService({
    required this.transactions,
    required this.rules,
    required this.recurring,
    required this.accounts,
    required this.local,
    this.cards,
    required this.sms,
    required this.gmail,
    this.onNewTransactions,
  });

  final TransactionRepository transactions;
  final RulesRepository rules;
  final RecurringRepository recurring;
  final ConnectedAccountsRepository accounts;
  final LocalStore local;

  /// Credit-card limits / statements read from issuer messages (optional).
  final CreditCardRepository? cards;
  final SmsSource sms;
  final GmailSource gmail;
  /// Called once per completed run ([initial] = first full import).
  final void Function(List<FinancialTransaction> txs, SyncProgress p, bool initial)? onNewTransactions;

  final _progress = StreamController<SyncProgress>.broadcast();
  SyncProgress _state = const SyncProgress();
  Future<SyncResult>? _running;

  SyncProgress get current => _state;
  Stream<SyncProgress> get progress async* {
    yield _state;
    yield* _progress.stream;
  }

  void _emit(SyncProgress p) {
    _state = p;
    _progress.add(p);
  }

  /// Runs a sync, or joins the one already in progress.
  Future<SyncResult> run(SyncRequest req) => _running ??= _run(req).whenComplete(() => _running = null);

  // ---------------------------------------------------------------------------

  late TransactionProcessor _processor;
  final _index = <String, _Indexed>{};
  final _new = <FinancialTransaction>[];

  Future<SyncResult> _run(SyncRequest req) async {
    final uid = req.ctx.userId;
    final wid = req.ctx.workspaceId;
    _new.clear();
    _index.clear();
    _emit(SyncProgress(stage: SyncStage.connecting, startedAt: DateTime.now(), queued: await local.pendingCount(uid)));

    try {
      final mappings = await rules.merchantMappings(wid).catchError((_) => <String, String>{});
      final extraTemplates = await rules.bankTemplates(wid);
      _processor = TransactionProcessor(
        parser: TransactionParser(templates: [...extraTemplates, ...defaultTemplates]),
        categorizer: CategorizationEngine(merchantMappings: mappings),
      );
      final now = DateTime.now().toUtc();
      final windowStart = now.subtract(Duration(days: (req.initial ? AppConfig.initialSyncDays : 45) + 2));
      final existing = await transactions.candidatesBetween(wid, windowStart, now.add(const Duration(days: 2))).catchError((_) => <FinancialTransaction>[]);
      _cardNumbers
        ..clear()
        ..addAll(cards == null ? const <String>{} : await cards!.cardNumbers(wid));
      for (final t in existing) {
        _index[t.transactionId] = _Indexed(DedupeCandidate.fromTransaction(t), t.sources, owner: t.ownerUserId);
      }
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.connect');
    }

    // Flush anything left over from a previous interrupted run first.
    await _flush(uid);

    if (req.includeSms) await _syncSms(req);
    if (req.includeGmail) await _syncGmail(req);

    _emit(_state.copyWith(stage: SyncStage.synchronizing));
    await _flush(uid);

    _emit(_state.copyWith(stage: SyncStage.generating));
    await _detectRecurring(req.ctx);

    final failedAll = _state.sources.isNotEmpty && _state.sources.values.every((s) => s.status == SourceSyncStatus.failed);
    _emit(_state.copyWith(stage: failedAll ? SyncStage.failed : SyncStage.completed, finishedAt: DateTime.now(), queued: await local.pendingCount(uid)));

    unawaited(accounts
        .log(uid, wid, {
          'initial': req.initial,
          'smsScanned': _state.smsScanned,
          'emailsScanned': _state.emailsScanned,
          'identified': _state.identified,
          'synced': _state.synced,
          'duplicates': _state.duplicates,
          'needsReview': _state.needsReview,
          'errors': {for (final e in _state.sources.entries) if (e.value.error != null) e.key: e.value.error},
        })
        .catchError((_) {}));

    final result = SyncResult(newTransactions: List.of(_new), progress: _state);
    onNewTransactions?.call(result.newTransactions, _state, req.initial);
    return result;
  }

  Future<void> _syncSms(SyncRequest req) async {
    final uid = req.ctx.userId;
    if (!sms.isSupported) {
      _emit(_state.withSource('sms', const SourceState(SourceSyncStatus.skipped, detail: 'SMS reading is not available on this platform')));
      return;
    }
    if (!await sms.hasPermission()) {
      _emit(_state.withSource('sms', const SourceState(SourceSyncStatus.skipped, detail: 'SMS permission not granted')));
      return;
    }
    _emit(_state.copyWith(stage: SyncStage.scanningSms).withSource('sms', const SourceState(SourceSyncStatus.running)));
    try {
      await _rescanAfterParserUpgrade(req.ctx);
      final cursorKey = '$uid:sms_last_id';
      final afterId = int.tryParse(await local.cursor(cursorKey) ?? '') ?? 0;
      final since = DateTime.now().subtract(Duration(days: AppConfig.initialSyncDays));
      final total = afterId == 0 ? await sms.count(since: since) : null;
      _emit(_state.copyWith(smsTotal: total ?? 0));

      var found = 0, scanned = 0;
      await for (final page in sms.read(since: since, afterId: afterId)) {
        scanned += page.length;
        found += await _ingest(page, req.ctx, onScanned: (n) => _emit(_state.copyWith(smsScanned: _state.smsScanned + n)));
        // Checkpoint only after the page is safely in the local outbox.
        await local.setCursor(cursorKey, page.last.id);
        await _flush(uid);
      }
      if (total == null) _emit(_state.copyWith(smsTotal: _state.smsScanned));
      await accounts.upsert(uid, req.ctx.workspaceId, SourceProvider.sms, ConnectionStatus.connected,
          identifier: 'Device SMS', scanned: scanned, found: found, synced: true);
      _emit(_state.withSource('sms', SourceState(SourceSyncStatus.done, detail: '$found transactions')));
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.sms');
      final f = ErrorHandler.map(e);
      _emit(_state.withSource('sms', SourceState(SourceSyncStatus.failed, error: f.message)));
      unawaited(accounts.upsert(uid, req.ctx.workspaceId, SourceProvider.sms, ConnectionStatus.error, error: f.message).catchError((_) {}));
    }
  }

  Future<void> _syncGmail(SyncRequest req) async {
    final uid = req.ctx.userId;
    final cursorKey = '$uid:gmail_history';
    try {
      if (!await gmail.isAuthorized()) {
        _emit(_state.withSource('gmail', const SourceState(SourceSyncStatus.skipped, detail: 'Gmail not connected')));
        return;
      }
    } catch (_) {
      _emit(_state.withSource('gmail', const SourceState(SourceSyncStatus.skipped, detail: 'Gmail not connected')));
      return;
    }
    _emit(_state.copyWith(stage: SyncStage.fetchingEmails).withSource('gmail', const SourceState(SourceSyncStatus.running)));
    try {
      final startHistory = await gmail.currentHistoryId();
      final cursor = await local.cursor(cursorKey);
      final ids = cursor == null
          ? await gmail.listInitial(days: AppConfig.initialSyncDays, estimate: (n) => _emit(_state.copyWith(emailsTotal: n)))
          : await gmail.listSince(cursor);
      final done = await local.processedKeys(uid, ids.map((i) => 'email:$i'));
      final todo = ids.where((i) => !done.contains('email:$i')).toList();
      _emit(_state.copyWith(emailsTotal: todo.length));

      var found = 0;
      const batch = 8;
      for (var i = 0; i < todo.length; i += batch) {
        final chunk = todo.sublist(i, i + batch > todo.length ? todo.length : i + batch);
        final msgs = (await Future.wait(chunk.map((id) => gmail.fetch(id).catchError((Object _) => null)))).whereType<RawMessage>().toList();
        final skipped = chunk.length - msgs.length;
        if (skipped > 0) _emit(_state.copyWith(emailsScanned: _state.emailsScanned + skipped));
        found += await _ingest(msgs, req.ctx, onScanned: (n) => _emit(_state.copyWith(emailsScanned: _state.emailsScanned + n)));
        if (i % 40 == 0) await _flush(uid);
      }
      await local.setCursor(cursorKey, startHistory);
      await accounts.upsert(uid, req.ctx.workspaceId, SourceProvider.gmail, ConnectionStatus.connected,
          scanned: todo.length, found: found, synced: true);
      _emit(_state.withSource('gmail', SourceState(SourceSyncStatus.done, detail: '$found transactions')));
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.gmail');
      final f = ErrorHandler.map(e);
      final reauth = f.code == 'gmail-unauthorized';
      _emit(_state.withSource('gmail', SourceState(SourceSyncStatus.failed, error: f.message)));
      unawaited(accounts
          .upsert(uid, req.ctx.workspaceId, SourceProvider.gmail, reauth ? ConnectionStatus.needsReauth : ConnectionStatus.error, error: f.message)
          .catchError((_) {}));
    }
  }

  /// Processes a batch of raw messages. Returns number of financial records queued.
  Future<int> _ingest(List<RawMessage> messages, ProcessingContext ctx, {required void Function(int) onScanned}) async {
    final uid = ctx.userId;
    final already = await local.processedKeys(uid, messages.map((m) => m.sourceKey));
    final ledger = <String, ({String status, String? txId})>{};
    var queued = 0;
    var identified = 0, categorized = 0, duplicates = 0, review = 0;

    for (final m in messages) {
      // Card facts (available limit, statement, payment) come from every
      // message, including spend alerts already saved as transactions.
      final card = _cardParser.parse(m);
      if (card != null) {
        _cardSnaps.add(card);
        _cardNumbers.add(card.last4);
      }
      final hint = _cardParser.parseHint(m);
      if (hint != null) _billHints.add(hint);
      if (already.contains(m.sourceKey)) continue;
      final out = _processor.process(m, ctx);
      final tx = out.transaction == null ? null : _asCreditCard(out.transaction!);
      if (tx == null) {
        // Not a payment — maybe a due reminder ("EMI … is due on …").
        final due = _dueParser.parse(m);
        if (due != null) _dues[due.key] = due;
        ledger[m.sourceKey] = (status: out.status.name, txId: null);
        continue;
      }
      identified++;
      if (!out.needsCategoryReview) categorized++;
      if (out.status == TxStatus.needsReview || out.needsCategoryReview) review++;

      final candidate = DedupeCandidate.fromTransaction(tx);
      final sameId = _index[tx.transactionId];
      final match = sameId != null
          ? DuplicateResult(DuplicateKind.sameEvent, match: sameId.candidate, score: 1)
          : const DuplicateDetector().check(candidate, _index.values.map((e) => e.candidate), sourceKey: m.sourceKey);

      final private = TransactionMapper.sourceToMap(out.sourceDetails!);
      if (match.isDuplicate) {
        duplicates++;
        final target = match.match!.transactionId;
        final indexed = _index[target]!;
        final mergedSources = {...indexed.sources, tx.source}.toList();
        final sourceNames = mergedSources.map((s) => s.name).toList();
        // Details only the newer message carries (reference no., account,
        // payee, bank). Only the record's owner may edit those fields.
        final fill = indexed.owner == uid ? _missingFields(indexed.candidate, tx) : const <String, dynamic>{};
        final pending = _pendingCreates.contains(target);
        await local.enqueue(OutboxEntry(
          txId: target,
          userId: uid,
          op: pending ? OutboxEntry.create : OutboxEntry.merge,
          payload: pending
              ? (_pendingPayloads[target]!
                ..addAll(fill)
                ..['sources'] = sourceNames)
              : {'sources': sourceNames, 'extractionConfidence': tx.extractionConfidence, ...fill},
          privatePayload: private,
        ));
        _index[target] = _Indexed(indexed.candidate.enrichedWith(candidate), mergedSources, owner: indexed.owner);
        ledger[m.sourceKey] = (status: TxStatus.duplicate.name, txId: target);
      } else {
        final payload = TransactionMapper.toJson(tx);
        await local.enqueue(OutboxEntry(txId: tx.transactionId, userId: uid, op: OutboxEntry.create, payload: payload, privatePayload: private));
        _pendingCreates.add(tx.transactionId);
        _pendingPayloads[tx.transactionId] = payload;
        _index[tx.transactionId] = _Indexed(candidate, [tx.source], owner: uid);
        _new.add(tx);
        queued++;
        ledger[m.sourceKey] = (status: tx.status.name, txId: tx.transactionId);
      }
    }
    await local.markProcessed(uid, ledger);
    onScanned(messages.length);
    if (identified > 0) {
      _emit(_state.copyWith(
        stage: _cycleStage(),
        identified: _state.identified + identified,
        categorized: _state.categorized + categorized,
        duplicates: _state.duplicates + duplicates,
        needsReview: _state.needsReview + review,
      ));
    }
    return queued;
  }

  /// Fields the canonical record lacks that the duplicate message provides.
  static Map<String, dynamic> _missingFields(DedupeCandidate existing, FinancialTransaction incoming) => {
        if (existing.referenceNumber == null && incoming.referenceNumber != null) 'referenceNumber': incoming.referenceNumber,
        if (existing.maskedAccount == null && incoming.maskedAccountNumber != null) 'maskedAccountNumber': incoming.maskedAccountNumber,
        if (existing.counterparty == null && incoming.counterparty != null) 'counterparty': incoming.counterparty,
        if (existing.bankName == null && incoming.bankName != null) 'bankName': incoming.bankName,
      };

  final _dueParser = DueReminderParser();
  final _cardParser = CardSmsParser();
  final _cardSnaps = <CardSnapshot>[];
  final _billHints = <BillPaymentHint>[];

  /// Last-4 digits of the user's credit cards: transactions on these numbers
  /// are credit-card spends even if the SMS just says "Card XX4007".
  final _cardNumbers = <String>{};

  FinancialTransaction _asCreditCard(FinancialTransaction t) {
    if (t.paymentMode == PaymentMode.creditCard) return t;
    final digits = (t.maskedAccountNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3) return t;
    final match = _cardNumbers.any((n) => digits.length >= 4 ? digits.endsWith(n) : n.endsWith(digits));
    if (!match) return t;
    return t.copyWith(
      paymentMode: PaymentMode.creditCard,
      transactionType: !t.isInflow && t.transactionType == TxType.debitCardPayment ? TxType.creditCardPayment : null,
    );
  }

  /// Latest reminder per obligation seen in this run.
  final _dues = <String, DueReminder>{};

  /// Saves due reminders to Upcoming, then marks dues settled by [txs] as paid.
  Future<void> _applyDues(ProcessingContext ctx, Iterable<FinancialTransaction> txs) async {
    try {
      for (final d in _dues.values) {
        await recurring.upsertFromReminder(ctx.workspaceId, ctx.userId, d);
      }
      _dues.clear();
      if (cards != null && _cardSnaps.isNotEmpty) {
        await cards!.apply(ctx.workspaceId, ctx.userId, List.of(_cardSnaps));
      }
      _cardSnaps.clear();
      if (cards != null && _billHints.isNotEmpty) await cards!.applyHints(ctx.workspaceId, List.of(_billHints));
      _billHints.clear();
      // Whenever the set of cards changes, re-label past "Debit Card" spends on them.
      if (cards != null) {
        final numbers = (await cards!.cardNumbers(ctx.workspaceId)).toList()..sort();
        final sigKey = '${ctx.userId}:card_mode_fix';
        final sig = 'v2:${numbers.join(',')}';
        if (numbers.isNotEmpty && await local.cursor(sigKey) != sig) {
          await cards!.fixPaymentModes(ctx.workspaceId, ctx.userId);
          await local.setCursor(sigKey, sig);
        }
      }
      final list = await recurring.list(ctx.workspaceId);
      final settled = <String>{};
      for (final p in const DuePaymentMatcher().match(list, txs)) {
        await recurring.markPaid(p.expense, p.dueDate);
        settled.add(p.expense.id);
      }
      // Card-bill entries (from "Pay Total Amount Due…" reminders) settle when
      // the card shows a payment: issuer "payment received" SMS or a matching
      // bank-side payment (e.g. SBI OTP to ICICI Bank Credit card).
      if (cards != null) {
        final cardList = await cards!.list(ctx.workspaceId);
        for (final r in list) {
          if (settled.contains(r.id) || r.status != RecurringStatus.active || r.categoryId != 'credit_card_payment') continue;
          final card = cardList.where((c) => (r.merchantKey ?? r.name).endsWith(c.last4)).firstOrNull;
          if (card == null) continue;
          final due = DateTime(r.nextDueDate.year, r.nextDueDate.month, r.nextDueDate.day);
          final payments = [
            if (card.lastPaymentAmount != null && card.lastPaymentAt != null) (amount: card.lastPaymentAmount!, at: card.lastPaymentAt!),
            ...card.paymentHints.where((h) => (h.amount - r.expectedAmount).abs() <= 1),
          ];
          final paid = payments.any((p) {
            final d = p.at.toLocal();
            return !d.isBefore(due.subtract(const Duration(days: 25))) && !d.isAfter(due.add(const Duration(days: 10))) && p.amount >= r.expectedAmount * 0.1;
          });
          if (paid) await recurring.markPaid(r, r.nextDueDate);
        }
      }
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.dues');
    }
  }

  /// Bump when parsing improves, so messages skipped by an older version are
  /// read once more (v2: due reminders, NACH/ACH credits, "Cr"/"has a credit";
  /// v3: "ACH/NAME/…", "NACH Credit/Debit", "Debit of Rs …" wordings;
  /// v4: amounts after "… LIMITED" / "BALAJI…" no longer mistaken for balances;
  /// v5: NACH debit payee names, SIP / mutual-fund debits → Investments;
  /// v6: credit-card limits / statements backfilled from the last 45 days;
  /// v7: card statements vs reminders, revisions, bank-side payment hints;
  /// v8: replay card messages so stale card dates are rebuilt;
  /// v9: rebuild card payments too (refunds were once counted as payments)).
  static const _parserVersion = 9;

  /// One-time look-back over the last 45 days (the duplicate-check window) after a parser upgrade:
  /// previously skipped messages are re-read (new transactions such as NACH
  /// dividend credits), and due reminders already in the inbox reach Upcoming.
  Future<void> _rescanAfterParserUpgrade(ProcessingContext ctx) async {
    final uid = ctx.userId;
    final key = '$uid:parser_version';
    if ((int.tryParse(await local.cursor(key) ?? '') ?? 1) >= _parserVersion) return;
    try {
      await local.forgetIgnored(uid);
      await for (final page in sms.read(since: DateTime.now().subtract(const Duration(days: 45)))) {
        // Reminders: keep only the latest due per obligation.
        for (final m in page) {
          final due = _dueParser.parse(m);
          if (due == null) continue;
          final prev = _dues[due.key];
          if (prev == null || due.dueDate.isAfter(prev.dueDate)) _dues[due.key] = due;
        }
        // Transactions: already-processed messages are skipped inside _ingest.
        await _ingest(page, ctx, onScanned: (_) {});
        await _flush(uid);
      }
      await local.setCursor(key, '$_parserVersion');
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.rescan');
    }
  }

  final _pendingCreates = <String>{};
  final _pendingPayloads = <String, Map<String, dynamic>>{};
  int _tick = 0;

  /// Rotates through the processing stages while messages stream in, so the
  /// status line reflects the work actually being performed.
  SyncStage _cycleStage() {
    const stages = [SyncStage.identifying, SyncStage.extracting, SyncStage.categorizing, SyncStage.counterparties, SyncStage.deduplicating];
    return stages[(_tick++) % stages.length];
  }

  Future<void> _flush(String uid) async {
    while (true) {
      final entries = await local.pending(uid, limit: 100);
      if (entries.isEmpty) break;
      var progressed = false;
      for (var i = 0; i < entries.length; i += 10) {
        final chunk = entries.sublist(i, i + 10 > entries.length ? entries.length : i + 10);
        final results = await Future.wait(chunk.map(_applyOne));
        for (var j = 0; j < chunk.length; j++) {
          final e = chunk[j];
          final r = results[j];
          if (r == null) {
            await local.removeFromOutbox(uid, e.txId);
            _pendingCreates.remove(e.txId);
            _pendingPayloads.remove(e.txId);
            if (e.op == OutboxEntry.create) _emit(_state.copyWith(synced: _state.synced + 1));
            progressed = true;
          } else {
            await local.markAttempt(uid, e.txId, r);
          }
        }
      }
      _emit(_state.copyWith(queued: await local.pendingCount(uid)));
      if (!progressed) break; // offline or failing — keep queued for later
    }
  }

  /// Returns null on success, or an error string.
  Future<String?> _applyOne(OutboxEntry e) async {
    try {
      await transactions.applyOutbox(e).timeout(const Duration(seconds: 20));
      return null;
    } on FirebaseException catch (ex) {
      if (ex.code == 'permission-denied' && e.op == OutboxEntry.create) {
        // Another member already created this canonical record (e.g. joint
        // account SMS). Fall back to attaching our source to it.
        try {
          await transactions.applyOutbox(OutboxEntry(
            txId: e.txId,
            userId: e.userId,
            op: OutboxEntry.merge,
            payload: {'sources': e.payload['sources'], 'extractionConfidence': e.payload['extractionConfidence']},
            privatePayload: e.privatePayload,
          ));
          return null;
        } catch (_) {
          return null; // not ours and not mergeable — drop safely
        }
      }
      if (ex.code == 'not-found' && e.op == OutboxEntry.merge) return null;
      return ex.code;
    } on TimeoutException {
      return 'timeout';
    } catch (ex) {
      return ex.toString();
    }
  }

  Future<void> _detectRecurring(ProcessingContext ctx) async {
    try {
      final now = AppClock.now();
      final txs = await transactions.getRange(ctx.workspaceId, DateTime(now.year - 1, now.month, 1), DateTime(now.year, now.month + 1, 1));
      final suggestions = const RecurringDetector().detect(txs);
      await recurring.upsertSuggestions(ctx.workspaceId, ctx.userId, suggestions);
      final recent = now.subtract(const Duration(days: 45));
      await _applyDues(ctx, txs.where((t) => AppClock.toLocal(t.transactionDate).isAfter(recent)));
    } catch (e, s) {
      ErrorHandler.log(e, s, 'sync.recurring');
      await _applyDues(ctx, const []); // still save reminders found this run
    }
  }

  /// Live SMS (foreground listener).
  Future<List<FinancialTransaction>> ingestLive(RawMessage m, ProcessingContext ctx) async {
    if (_running != null) await _running;
    _new.clear();
    final mappings = await rules.merchantMappings(ctx.workspaceId).catchError((_) => <String, String>{});
    _processor = TransactionProcessor(categorizer: CategorizationEngine(merchantMappings: mappings));
    final now = DateTime.now().toUtc();
    final existing = await transactions
        .candidatesBetween(ctx.workspaceId, now.subtract(const Duration(days: 3)), now.add(const Duration(days: 1)))
        .catchError((_) => <FinancialTransaction>[]);
    _index
      ..clear()
      ..addEntries(existing.map((t) => MapEntry(t.transactionId, _Indexed(DedupeCandidate.fromTransaction(t), t.sources, owner: t.ownerUserId))));
    if (cards != null) {
      _cardNumbers
        ..clear()
        ..addAll(await cards!.cardNumbers(ctx.workspaceId));
    }
    await _ingest([m], ctx, onScanned: (_) {});
    await _flush(ctx.userId);
    await _applyDues(ctx, _new);
    return List.of(_new);
  }

  Future<void> resetCheckpoints(String uid) => local.clearUser(uid);
}

class _Indexed {
  _Indexed(this.candidate, this.sources, {this.owner});
  final DedupeCandidate candidate;
  final List<TxSource> sources;

  /// ownerUserId of the canonical record (who may enrich its fields).
  final String? owner;
}
