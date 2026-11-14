import '../transaction_enums.dart';

/// A message from an authorized source (SMS inbox or connected mailbox),
/// before any financial interpretation.
class RawMessage {
  const RawMessage({
    required this.id,
    required this.source,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.subject,
    this.senderName,
  });

  /// Stable provider identifier (SMS `_id`, Gmail message id).
  final String id;
  final TxSource source;

  /// SMS sender ID (e.g. "VM-HDFCBK") or email address.
  final String sender;

  /// Email display name, when available.
  final String? senderName;
  final String? subject;
  final String body;
  final DateTime receivedAt;

  String get sourceKey => '${source.name}:$id';
}

enum ExtractionStatus { success, needsReview, ignored, failed }

/// Structured result of the extraction step.
class ExtractedTransaction {
  const ExtractedTransaction({
    required this.status,
    required this.message,
    this.ignoreReason,
    this.amount,
    this.currency = 'INR',
    this.direction,
    this.type,
    this.paymentMode = PaymentMode.other,
    this.transactionDate,
    this.hasExplicitDate = false,
    this.hasExplicitTime = false,
    this.bankName,
    this.maskedAccount,
    this.merchant,
    this.counterparty,
    this.upiId,
    this.referenceNumber,
    this.originalNarration,
    this.normalizedNarration = '',
    this.confidence = 0,
    this.isFailedTransaction = false,
    this.isInternalTransfer = false,
    this.missingFields = const [],
  });

  factory ExtractedTransaction.ignored(RawMessage m, String reason) =>
      ExtractedTransaction(status: ExtractionStatus.ignored, message: m, ignoreReason: reason);

  final ExtractionStatus status;
  final RawMessage message;
  final String? ignoreReason;
  final double? amount;
  final String currency;
  final TxDirection? direction;
  final TxType? type;
  final PaymentMode paymentMode;

  /// Wall-clock date/time printed by the bank (falls back to receivedAt).
  final DateTime? transactionDate;
  final bool hasExplicitDate;
  final bool hasExplicitTime;
  final String? bankName;
  final String? maskedAccount;
  final String? merchant;
  final String? counterparty;
  final String? upiId;
  final String? referenceNumber;
  final String? originalNarration;
  final String normalizedNarration;
  final double confidence;
  final bool isFailedTransaction;
  final bool isInternalTransfer;
  final List<String> missingFields;

  bool get isFinancial => status == ExtractionStatus.success || status == ExtractionStatus.needsReview;
}
