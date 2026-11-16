import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/failures.dart';
import '../../../core/utils/app_clock.dart';
import '../../sync/data/local_store.dart';
import '../domain/category.dart';
import '../domain/engines/duplicate_detector.dart';
import '../domain/engines/transaction_processor.dart';
import '../domain/transaction.dart';
import '../domain/transaction_enums.dart';
import '../domain/transaction_filter.dart';
import 'transaction_mapper.dart';

class TransactionPage {
  const TransactionPage(this.items, this.cursor, this.hasMore);
  final List<FinancialTransaction> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class TransactionRepository {
  TransactionRepository(this._db);
  final FirebaseFirestore _db;

  /// Hard cap for date-scoped dashboard queries; never load whole collection.
  static const rangeLimit = 2500;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('transactions');

  Query<Map<String, dynamic>> _range(String workspaceId, DateTime startLocal, DateTime endLocal) => _col
      .where('workspaceId', isEqualTo: workspaceId)
      .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(AppClock.toUtc(startLocal)))
      .where('transactionDate', isLessThan: Timestamp.fromDate(AppClock.toUtc(endLocal)))
      .orderBy('transactionDate', descending: true);

  /// Live, date-scoped transactions for the dashboard. Served from the local
  /// Firestore cache first, then refreshed from the server.
  Stream<List<FinancialTransaction>> watchRange(String workspaceId, DateTime startLocal, DateTime endLocal) =>
      _range(workspaceId, startLocal, endLocal)
          .limit(rangeLimit)
          .snapshots()
          .map((q) => DuplicateDetector.collapse(q.docs.map(TransactionMapper.fromFirestore).toList()));

  Future<List<FinancialTransaction>> getRange(String workspaceId, DateTime startLocal, DateTime endLocal, {int limit = rangeLimit}) async {
    final q = await _range(workspaceId, startLocal, endLocal).limit(limit).get();
    return DuplicateDetector.collapse(q.docs.map(TransactionMapper.fromFirestore).toList());
  }

  Stream<List<FinancialTransaction>> watchRecent(String workspaceId, {int limit = 8}) => _col
      .where('workspaceId', isEqualTo: workspaceId)
      .orderBy('transactionDate', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => DuplicateDetector.collapse(q.docs.map(TransactionMapper.fromFirestore).toList()));

  Stream<FinancialTransaction?> watch(String id) =>
      _col.doc(id).snapshots().map((s) => s.exists ? TransactionMapper.fromFirestore(s) : null);

  /// Owner-only source details (rules deny others).
  Future<TransactionSourceDetails?> sourceDetails(String id, String uid) async {
    try {
      final s = await _col.doc(id).collection('private').doc(uid).get();
      return s.exists ? TransactionMapper.sourceFromMap(s.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  /// Cursor-paginated history. One selective filter is pushed to Firestore
  /// (needs a composite index); the rest are applied to the fetched page.
  Future<TransactionPage> page(String workspaceId, TransactionFilter f,
      {DocumentSnapshot<Map<String, dynamic>>? after, int pageSize = 30}) async {
    try {
      Query<Map<String, dynamic>> q = _col.where('workspaceId', isEqualTo: workspaceId);
      final server = f.serverSideField;
      switch (server) {
        case FilterField.search:
          q = q.where('searchKeywords', arrayContains: f.searchToken);
        case FilterField.category:
          q = q.where('categoryId', isEqualTo: f.categoryId);
        case FilterField.direction:
          q = q.where('direction', isEqualTo: f.direction!.name);
        case FilterField.owner:
          q = q.where('ownerUserId', isEqualTo: f.ownerUserId);
        case FilterField.source:
          q = q.where('sources', arrayContains: f.source!.name);
        case null:
          break;
      }
      q = q
          .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(AppClock.toUtc(f.period.start)))
          .where('transactionDate', isLessThan: Timestamp.fromDate(AppClock.toUtc(f.period.end)))
          .orderBy('transactionDate', descending: true);

      final items = <FinancialTransaction>[];
      var cursor = after;
      var hasMore = true;
      // Keep fetching until the page is filled after client-side filtering.
      for (var round = 0; round < 5 && items.length < pageSize && hasMore; round++) {
        var qq = q.limit(pageSize);
        if (cursor != null) qq = qq.startAfterDocument(cursor);
        final snap = await qq.get();
        hasMore = snap.docs.length == pageSize;
        if (snap.docs.isNotEmpty) cursor = snap.docs.last;
        items.addAll(snap.docs.map(TransactionMapper.fromFirestore).where((t) => f.matches(t, skip: server)));
      }
      return TransactionPage(DuplicateDetector.collapse(items), cursor, hasMore);
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Existing records in a window, used as duplicate-detection candidates.
  Future<List<FinancialTransaction>> candidatesBetween(String workspaceId, DateTime fromUtc, DateTime toUtc) async {
    final q = await _col
        .where('workspaceId', isEqualTo: workspaceId)
        .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(fromUtc))
        .where('transactionDate', isLessThan: Timestamp.fromDate(toUtc))
        .orderBy('transactionDate', descending: true)
        .limit(5000)
        .get();
    return q.docs.map(TransactionMapper.fromFirestore).toList();
  }

  /// Flushes one outbox entry. Writes are idempotent: document IDs are
  /// deterministic and merges use arrayUnion.
  /// Fields a dedupe merge may fill in when the canonical record lacks them.
  static const enrichableFields = ['referenceNumber', 'maskedAccountNumber', 'counterparty', 'bankName'];

  Future<void> applyOutbox(OutboxEntry e) async {
    final ref = _col.doc(e.txId);
    final privateRef = ref.collection('private').doc(e.userId);
    if (e.op == OutboxEntry.create) {
      final tx = TransactionMapper.fromMap(e.payload, id: e.txId);
      await ref.set(TransactionMapper.toFirestore(tx));
    } else {
      // Owner merges may also fill details the first message lacked.
      final fill = {
        for (final k in enrichableFields)
          if (e.payload[k] != null) k: e.payload[k],
      };
      await ref.update({
        'sources': FieldValue.arrayUnion(List<String>.from(e.payload['sources'] as List)),
        'contributors': FieldValue.arrayUnion([e.userId]),
        'extractionConfidence': e.payload['extractionConfidence'],
        'updatedAt': FieldValue.serverTimestamp(),
        ...fill,
        if (fill.isNotEmpty)
          'searchKeywords': FieldValue.arrayUnion(
            TransactionProcessor.buildSearchKeywords([fill['counterparty'] as String?, fill['referenceNumber'] as String?, fill['bankName'] as String?]),
          ),
      });
    }
    if (e.privatePayload != null) {
      await privateRef.set({
        ...e.privatePayload!,
        'sourceMessageIds': FieldValue.arrayUnion(List<String>.from(e.privatePayload!['sourceMessageIds'] as List? ?? const [])),
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateClassification(
    FinancialTransaction t, {
    required CategoryDef category,
    String? subcategory,
    String? counterparty,
  }) async {
    try {
      await _col.doc(t.transactionId).update({
        'categoryId': category.id,
        'categoryName': category.name,
        'categoryIcon': category.iconKey,
        'subcategory': subcategory,
        if (counterparty != null) 'counterparty': counterparty,
        if (counterparty != null)
          'searchKeywords': TransactionProcessor.buildSearchKeywords([counterparty, t.merchant, t.narration, t.referenceNumber, t.bankName]),
        'categoryConfidence': 1.0,
        'userCorrected': true,
        if (t.status == TxStatus.needsReview && category.id != Categories.others.id) 'status': TxStatus.success.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Fills in a payee the record was saved without (an older parser missed
  /// it), with the matching narration and search words. The category is
  /// replaced only while it is still "Others" and the user hasn't set it.
  /// Returns true when something changed.
  Future<bool> fillMissingPayee(String id, FinancialTransaction parsed) async {
    final cp = parsed.counterparty;
    if (cp == null) return false;
    final ref = _col.doc(id);
    final snap = await ref.get();
    final d = snap.data();
    if (d == null || d['counterparty'] != null) return false;
    final recategorize = d['userCorrected'] != true && d['categoryId'] == Categories.others.id && parsed.categoryId != Categories.others.id;
    await ref.update({
      'counterparty': cp,
      'merchant': d['merchant'] ?? parsed.merchant,
      'narration': parsed.narration,
      'searchKeywords': FieldValue.arrayUnion(TransactionProcessor.buildSearchKeywords([cp, parsed.merchant, parsed.narration])),
      if (recategorize) ...{
        'categoryId': parsed.categoryId,
        'categoryName': parsed.categoryName,
        'subcategory': parsed.subcategory,
        'categoryConfidence': parsed.categoryConfidence,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// After the user files a payee under a category ("apply to this
  /// merchant"), moves their other transactions from that payee that are still
  /// in "Others" to it. Records the user can't edit (another member's) or has
  /// categorised by hand are left alone. Returns how many changed.
  Future<int> applyCategoryToPayee({
    required String workspaceId,
    required String counterparty,
    required CategoryDef category,
    String? subcategory,
    required String exceptId,
  }) async {
    try {
      final q = await _col
          .where('workspaceId', isEqualTo: workspaceId)
          .where('counterparty', isEqualTo: counterparty)
          .where('categoryId', isEqualTo: Categories.others.id)
          .limit(300)
          .get();
      var changed = 0;
      for (final d in q.docs) {
        if (d.id == exceptId || d.data()['userCorrected'] == true) continue;
        try {
          await d.reference.update({
            'categoryId': category.id,
            'categoryName': category.name,
            'categoryIcon': category.iconKey,
            'subcategory': subcategory,
            'categoryConfidence': 1.0,
            if (d.data()['status'] == TxStatus.needsReview.name) 'status': TxStatus.success.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          changed++;
        } catch (_) {
          // Not ours to edit — skip.
        }
      }
      return changed;
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> setStatus(String id, TxStatus status) => _col.doc(id).update({'status': status.name, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> setInternalTransfer(String id, bool value) =>
      _col.doc(id).update({'isInternalTransfer': value, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> createManual(FinancialTransaction t) async {
    try {
      await _col.doc(t.transactionId).set(TransactionMapper.toFirestore(t));
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  Future<void> delete(String id, String uid) async {
    try {
      await _col.doc(id).collection('private').doc(uid).delete();
      await _col.doc(id).delete();
    } catch (e) {
      throw ErrorHandler.map(e);
    }
  }

  /// Removes [dropId], a second copy of the same event, after moving its
  /// source message ids onto [keepId] so neither is re-imported.
  Future<void> removeDuplicate({required String keepId, required String dropId, required String uid, required List<String> messageIds}) async {
    await _col.doc(keepId).collection('private').doc(uid).set(
      {'sourceMessageIds': FieldValue.arrayUnion(messageIds)},
      SetOptions(merge: true),
    );
    await delete(dropId, uid);
  }

  String newId() => _col.doc().id;
}
