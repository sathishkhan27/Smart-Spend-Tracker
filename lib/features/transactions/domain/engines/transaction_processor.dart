import '../../../../core/utils/app_clock.dart';
import '../transaction.dart';
import '../transaction_enums.dart';
import 'categorization_engine.dart';
import 'duplicate_detector.dart';
import 'raw_message.dart';
import 'transaction_parser.dart';

class ProcessingContext {
  const ProcessingContext({required this.workspaceId, required this.userId, this.userName});
  final String workspaceId;
  final String userId;
  final String? userName;
}

class ProcessingOutcome {
  const ProcessingOutcome({required this.status, required this.extracted, this.transaction, this.sourceDetails, this.needsCategoryReview = false});
  final TxStatus status;
  final ExtractedTransaction extracted;
  final FinancialTransaction? transaction;
  final TransactionSourceDetails? sourceDetails;
  final bool needsCategoryReview;
}

/// Steps 1–11 of the processing flow: detect → extract → validate → identify
/// institution/counterparty/direction → normalize → categorize → fingerprint.
/// Duplicate checking and persistence (steps 12–14) happen in the sync layer,
/// which has access to existing records.
class TransactionProcessor {
  TransactionProcessor({TransactionParser? parser, CategorizationEngine? categorizer})
      : parser = parser ?? TransactionParser(),
        categorizer = categorizer ?? CategorizationEngine();

  final TransactionParser parser;
  final CategorizationEngine categorizer;

  ProcessingOutcome process(RawMessage message, ProcessingContext ctx, {DateTime? now}) {
    final x = parser.parse(message);
    if (x.status == ExtractionStatus.ignored) {
      return ProcessingOutcome(status: TxStatus.ignored, extracted: x);
    }
    if (x.amount == null) return ProcessingOutcome(status: TxStatus.failed, extracted: x);

    final direction = x.direction ?? TxDirection.outflow;
    final type = x.type ?? (direction == TxDirection.inflow ? TxType.credit : TxType.debit);
    final cat = categorizer.categorize(CategorizationInput(
      direction: direction,
      type: type,
      paymentMode: x.paymentMode,
      merchant: x.merchant,
      counterparty: x.counterparty,
      narration: x.originalNarration ?? '',
      upiId: x.upiId,
    ));

    final TxStatus status;
    if (x.isFailedTransaction) {
      status = TxStatus.failed;
    } else if (x.status == ExtractionStatus.needsReview) {
      status = TxStatus.needsReview;
    } else {
      status = TxStatus.success;
    }

    final dateUtc = AppClock.toUtc(x.transactionDate ?? message.receivedAt);
    final ts = (now ?? DateTime.now()).toUtc();
    final id = DuplicateDetector.transactionIdFor(
      workspaceId: ctx.workspaceId,
      amount: x.amount!,
      direction: direction,
      referenceNumber: x.referenceNumber,
      sourceKey: message.sourceKey,
    );

    final tx = FinancialTransaction(
      transactionId: id,
      workspaceId: ctx.workspaceId,
      ownerUserId: ctx.userId,
      ownerName: ctx.userName,
      amount: x.amount!,
      currency: x.currency,
      direction: direction,
      transactionType: type,
      categoryId: cat.category.id,
      categoryName: cat.category.name,
      subcategory: cat.subcategory,
      counterparty: x.counterparty,
      merchant: x.merchant,
      narration: x.normalizedNarration,
      transactionDate: dateUtc,
      bankName: x.bankName,
      maskedAccountNumber: x.maskedAccount,
      paymentMode: x.paymentMode,
      referenceNumber: x.referenceNumber,
      upiId: x.upiId,
      source: message.source,
      sources: [message.source],
      status: status,
      isInternalTransfer: x.isInternalTransfer,
      categoryConfidence: cat.confidence,
      extractionConfidence: x.confidence,
      fingerprint: DuplicateDetector.fingerprint(
        amount: x.amount!,
        direction: direction,
        dateUtc: dateUtc,
        maskedAccount: x.maskedAccount,
        referenceNumber: x.referenceNumber,
      ),
      searchKeywords: buildSearchKeywords([x.counterparty, x.merchant, x.normalizedNarration, x.referenceNumber, x.bankName, x.upiId]),
      createdAt: ts,
      updatedAt: ts,
    );

    return ProcessingOutcome(
      status: status,
      extracted: x,
      transaction: tx,
      needsCategoryReview: cat.needsReview,
      sourceDetails: TransactionSourceDetails(
        sourceMessageIds: [message.sourceKey],
        smsSender: message.source == TxSource.sms ? message.sender : null,
        emailSender: message.source == TxSource.email ? message.sender : null,
        emailSubject: message.subject,
        originalNarration: x.originalNarration,
      ),
    );
  }

  /// Lower-case tokens and prefixes (≥3 chars) used for Firestore
  /// `array-contains` search on merchant, counterparty, narration and reference.
  static List<String> buildSearchKeywords(List<String?> fields) {
    final out = <String>{};
    for (final f in fields.whereType<String>()) {
      for (final word in f.toLowerCase().split(RegExp(r'[^a-z0-9@]+'))) {
        if (word.length < 3) continue;
        final limit = word.length > 15 ? 15 : word.length;
        for (var i = 3; i <= limit; i++) {
          out.add(word.substring(0, i));
        }
        out.add(word);
      }
    }
    return out.take(150).toList();
  }
}
