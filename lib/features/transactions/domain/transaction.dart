import 'category.dart';
import 'transaction_enums.dart';

/// Canonical, workspace-shared financial transaction.
///
/// Sensitive source details (raw narration, SMS sender, message IDs) are NOT
/// part of this entity; they live in [TransactionSourceDetails] which only the
/// contributing user can read.
class FinancialTransaction {
  const FinancialTransaction({
    required this.transactionId,
    required this.workspaceId,
    required this.ownerUserId,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.transactionType,
    required this.categoryId,
    required this.categoryName,
    required this.transactionDate,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.ownerName,
    this.subcategory,
    this.counterparty,
    this.merchant,
    this.narration = '',
    this.bankName,
    this.maskedAccountNumber,
    this.paymentMode = PaymentMode.other,
    this.referenceNumber,
    this.upiId,
    this.sources = const [],
    this.isRecurring = false,
    this.isInternalTransfer = false,
    this.categoryConfidence = 0,
    this.extractionConfidence = 0,
    this.fingerprint,
    this.searchKeywords = const [],
  });

  final String transactionId;
  final String workspaceId;
  final String ownerUserId;
  final String? ownerName;
  final double amount;
  final String currency;
  final TxDirection direction;
  final TxType transactionType;
  final String categoryId;
  final String categoryName;
  final String? subcategory;
  final String? counterparty;
  final String? merchant;

  /// Normalized narration — safe to share with workspace members.
  final String narration;

  /// Bank wall-clock date/time stored as UTC instant.
  final DateTime transactionDate;
  final String? bankName;

  /// Always masked, e.g. "XX1234".
  final String? maskedAccountNumber;
  final PaymentMode paymentMode;
  final String? referenceNumber;
  final String? upiId;

  /// Primary source of the canonical transaction.
  final TxSource source;

  /// All sources that reported this financial event (sms, email).
  final List<TxSource> sources;
  final TxStatus status;
  final bool isRecurring;
  final bool isInternalTransfer;
  final double categoryConfidence;
  final double extractionConfidence;
  final String? fingerprint;
  final List<String> searchKeywords;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isInflow => direction == TxDirection.inflow;
  CategoryDef get category => Categories.byId(categoryId);
  String get displayName => counterparty ?? merchant ?? bankName ?? transactionType.label;

  /// Whether this transaction counts toward confirmed inflow/outflow totals.
  bool get countsTowardTotals => status == TxStatus.success && !isInternalTransfer;

  FinancialTransaction copyWith({
    PaymentMode? paymentMode,
    TxType? transactionType,
    String? categoryId,
    String? categoryName,
    String? subcategory,
    String? counterparty,
    TxStatus? status,
    bool? isRecurring,
    bool? isInternalTransfer,
    double? categoryConfidence,
    List<TxSource>? sources,
    double? extractionConfidence,
    DateTime? updatedAt,
    List<String>? searchKeywords,
  }) =>
      FinancialTransaction(
        transactionId: transactionId,
        workspaceId: workspaceId,
        ownerUserId: ownerUserId,
        ownerName: ownerName,
        amount: amount,
        currency: currency,
        direction: direction,
        transactionType: transactionType ?? this.transactionType,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName ?? this.categoryName,
        subcategory: subcategory ?? this.subcategory,
        counterparty: counterparty ?? this.counterparty,
        merchant: merchant,
        narration: narration,
        transactionDate: transactionDate,
        bankName: bankName,
        maskedAccountNumber: maskedAccountNumber,
        paymentMode: paymentMode ?? this.paymentMode,
        referenceNumber: referenceNumber,
        upiId: upiId,
        source: source,
        sources: sources ?? this.sources,
        status: status ?? this.status,
        isRecurring: isRecurring ?? this.isRecurring,
        isInternalTransfer: isInternalTransfer ?? this.isInternalTransfer,
        categoryConfidence: categoryConfidence ?? this.categoryConfidence,
        extractionConfidence: extractionConfidence ?? this.extractionConfidence,
        fingerprint: fingerprint,
        searchKeywords: searchKeywords ?? this.searchKeywords,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Owner-only details about where a transaction came from.
class TransactionSourceDetails {
  const TransactionSourceDetails({
    required this.sourceMessageIds,
    this.smsSender,
    this.emailSender,
    this.emailSubject,
    this.originalNarration,
  });

  final List<String> sourceMessageIds;
  final String? smsSender;
  final String? emailSender;
  final String? emailSubject;

  /// Trimmed narration line only — never the full SMS/email body.
  final String? originalNarration;
}
