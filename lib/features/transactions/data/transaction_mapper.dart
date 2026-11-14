import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../domain/transaction.dart';
import '../domain/transaction_enums.dart';

/// Firestore ⇄ domain mapping for transactions.
abstract final class TransactionMapper {
  static Map<String, dynamic> toFirestore(FinancialTransaction t) => _toMap(t, (d) => Timestamp.fromDate(d.toUtc()));

  /// JSON-safe representation used by the local outbox.
  static Map<String, dynamic> toJson(FinancialTransaction t) => _toMap(t, (d) => d.toUtc().millisecondsSinceEpoch);

  static Map<String, dynamic> _toMap(FinancialTransaction t, Object Function(DateTime) date) {
    final local = AppClock.toLocal(t.transactionDate);
    return {
      'transactionId': t.transactionId,
      'workspaceId': t.workspaceId,
      'ownerUserId': t.ownerUserId,
      'ownerName': t.ownerName,
      'amount': t.amount,
      'currency': t.currency,
      'direction': t.direction.name,
      'transactionType': t.transactionType.name,
      'categoryId': t.categoryId,
      'categoryName': t.categoryName,
      'categoryIcon': t.category.iconKey,
      'subcategory': t.subcategory,
      'counterparty': t.counterparty,
      'merchant': t.merchant,
      'narration': t.narration,
      'transactionDate': date(t.transactionDate),
      'transactionTime': Fmt.time(local),
      'dayKey': Fmt.dayKey(local),
      'monthKey': Fmt.monthKey(local),
      'bankName': t.bankName,
      'maskedAccountNumber': t.maskedAccountNumber,
      'paymentMode': t.paymentMode.name,
      'referenceNumber': t.referenceNumber,
      'upiId': t.upiId,
      'source': t.source.name,
      'sources': t.sources.map((e) => e.name).toList(),
      'status': t.status.name,
      'isRecurring': t.isRecurring,
      'isInternalTransfer': t.isInternalTransfer,
      'categoryConfidence': t.categoryConfidence,
      'extractionConfidence': t.extractionConfidence,
      'fingerprint': t.fingerprint,
      'searchKeywords': t.searchKeywords,
      'createdAt': date(t.createdAt),
      'updatedAt': date(t.updatedAt),
    };
  }

  static FinancialTransaction fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.data() ?? const {}, id: doc.id);

  static FinancialTransaction fromMap(Map<String, dynamic> d, {String? id}) {
    final dir = enumByName(TxDirection.values, d['direction'], TxDirection.outflow);
    return FinancialTransaction(
      transactionId: id ?? d['transactionId'] as String,
      workspaceId: d['workspaceId'] as String? ?? '',
      ownerUserId: d['ownerUserId'] as String? ?? '',
      ownerName: d['ownerName'] as String?,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'INR',
      direction: dir,
      transactionType: enumByName(TxType.values, d['transactionType'], dir == TxDirection.inflow ? TxType.credit : TxType.debit),
      categoryId: d['categoryId'] as String? ?? 'others',
      categoryName: d['categoryName'] as String? ?? 'Others',
      subcategory: d['subcategory'] as String?,
      counterparty: d['counterparty'] as String?,
      merchant: d['merchant'] as String?,
      narration: d['narration'] as String? ?? '',
      transactionDate: _date(d['transactionDate']),
      bankName: d['bankName'] as String?,
      maskedAccountNumber: d['maskedAccountNumber'] as String?,
      paymentMode: enumByName(PaymentMode.values, d['paymentMode'], PaymentMode.other),
      referenceNumber: d['referenceNumber'] as String?,
      upiId: d['upiId'] as String?,
      source: enumByName(TxSource.values, d['source'], TxSource.manual),
      sources: [for (final s in (d['sources'] as List? ?? const [])) enumByName(TxSource.values, s, TxSource.manual)],
      status: enumByName(TxStatus.values, d['status'], TxStatus.success),
      isRecurring: d['isRecurring'] as bool? ?? false,
      isInternalTransfer: d['isInternalTransfer'] as bool? ?? false,
      categoryConfidence: (d['categoryConfidence'] as num?)?.toDouble() ?? 0,
      extractionConfidence: (d['extractionConfidence'] as num?)?.toDouble() ?? 0,
      fingerprint: d['fingerprint'] as String?,
      searchKeywords: List<String>.from(d['searchKeywords'] as List? ?? const []),
      createdAt: _date(d['createdAt']),
      updatedAt: _date(d['updatedAt']),
    );
  }

  static Map<String, dynamic> sourceToMap(TransactionSourceDetails s) => {
        'sourceMessageIds': s.sourceMessageIds,
        'smsSender': s.smsSender,
        'emailSender': s.emailSender,
        'emailSubject': s.emailSubject,
        'originalNarration': s.originalNarration,
      };

  static TransactionSourceDetails sourceFromMap(Map<String, dynamic> d) => TransactionSourceDetails(
        sourceMessageIds: List<String>.from(d['sourceMessageIds'] as List? ?? const []),
        smsSender: d['smsSender'] as String?,
        emailSender: d['emailSender'] as String?,
        emailSubject: d['emailSubject'] as String?,
        originalNarration: d['originalNarration'] as String?,
      );

  static DateTime _date(Object? v) => switch (v) {
        Timestamp t => t.toDate().toUtc(),
        int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        String s => DateTime.tryParse(s)?.toUtc() ?? DateTime.now().toUtc(),
        _ => DateTime.now().toUtc(),
      };
}
