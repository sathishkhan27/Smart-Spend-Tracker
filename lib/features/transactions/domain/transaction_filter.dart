import '../../../core/utils/date_range.dart';
import 'transaction.dart';
import 'transaction_enums.dart';

enum FilterField { search, category, direction, owner, source }

class TransactionFilter {
  const TransactionFilter({
    required this.period,
    this.direction,
    this.categoryId,
    this.subcategory,
    this.counterparty,
    this.bankName,
    this.paymentMode,
    this.ownerUserId,
    this.source,
    this.search = '',
    this.status,
  });

  final DateRangePeriod period;
  final TxDirection? direction;
  final String? categoryId;
  final String? subcategory;
  final String? counterparty;
  final String? bankName;
  final PaymentMode? paymentMode;
  final String? ownerUserId;
  final TxSource? source;
  final String search;
  final TxStatus? status;

  String? get searchToken {
    final words = search.toLowerCase().split(RegExp(r'[^a-z0-9@]+')).where((w) => w.length >= 3).toList();
    if (words.isEmpty) return null;
    words.sort((a, b) => b.length.compareTo(a.length));
    final w = words.first;
    return w.length > 15 ? w.substring(0, 15) : w;
  }

  /// The single most selective filter executed by Firestore.
  FilterField? get serverSideField {
    if (searchToken != null) return FilterField.search;
    if (categoryId != null) return FilterField.category;
    if (direction != null) return FilterField.direction;
    if (ownerUserId != null) return FilterField.owner;
    if (source != null) return FilterField.source;
    return null;
  }

  int get activeCount => [direction, categoryId, subcategory, counterparty, bankName, paymentMode, ownerUserId, source, status]
      .where((e) => e != null)
      .length;

  bool matches(FinancialTransaction t, {FilterField? skip}) {
    if (skip != FilterField.direction && direction != null && t.direction != direction) return false;
    if (skip != FilterField.category && categoryId != null && t.categoryId != categoryId) return false;
    if (skip != FilterField.owner && ownerUserId != null && t.ownerUserId != ownerUserId) return false;
    if (skip != FilterField.source && source != null && !t.sources.contains(source) && t.source != source) return false;
    if (subcategory != null && t.subcategory != subcategory) return false;
    if (counterparty != null && (t.counterparty ?? '').toLowerCase() != counterparty!.toLowerCase()) return false;
    if (bankName != null && t.bankName != bankName) return false;
    if (paymentMode != null && t.paymentMode != paymentMode) return false;
    if (status != null && t.status != status) return false;
    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase().trim();
      final hay = [t.counterparty, t.merchant, t.narration, t.referenceNumber, t.categoryName].whereType<String>().join(' ').toLowerCase();
      final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
      if (!(words.isEmpty ? hay.contains(q) : words.every(hay.contains))) return false;
    }
    return true;
  }

  TransactionFilter copyWith({
    DateRangePeriod? period,
    Object? direction = _keep,
    Object? categoryId = _keep,
    Object? subcategory = _keep,
    Object? counterparty = _keep,
    Object? bankName = _keep,
    Object? paymentMode = _keep,
    Object? ownerUserId = _keep,
    Object? source = _keep,
    Object? status = _keep,
    String? search,
  }) =>
      TransactionFilter(
        period: period ?? this.period,
        direction: direction == _keep ? this.direction : direction as TxDirection?,
        categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
        subcategory: subcategory == _keep ? this.subcategory : subcategory as String?,
        counterparty: counterparty == _keep ? this.counterparty : counterparty as String?,
        bankName: bankName == _keep ? this.bankName : bankName as String?,
        paymentMode: paymentMode == _keep ? this.paymentMode : paymentMode as PaymentMode?,
        ownerUserId: ownerUserId == _keep ? this.ownerUserId : ownerUserId as String?,
        source: source == _keep ? this.source : source as TxSource?,
        status: status == _keep ? this.status : status as TxStatus?,
        search: search ?? this.search,
      );

  TransactionFilter cleared() => TransactionFilter(period: period, search: search);

  static const _keep = Object();
}
