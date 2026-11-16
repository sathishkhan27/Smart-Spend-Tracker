import '../category.dart';
import '../transaction_enums.dart';

class CategorizationResult {
  const CategorizationResult(this.category, this.subcategory, this.confidence, {this.needsReview = false, this.matchedBy = ''});
  final CategoryDef category;
  final String? subcategory;
  final double confidence;
  final bool needsReview;
  final String matchedBy;
}

class CategorizationInput {
  const CategorizationInput({
    required this.direction,
    required this.type,
    required this.paymentMode,
    this.merchant,
    this.counterparty,
    this.narration = '',
    this.upiId,
  });
  final TxDirection direction;
  final TxType type;
  final PaymentMode paymentMode;
  final String? merchant;
  final String? counterparty;
  final String narration;
  final String? upiId;
}

/// Deterministic, rule-based categorizer. Learns from user corrections via
/// [merchantMappings] (normalized merchant key → category id[/subcategory]).
class CategorizationEngine {
  CategorizationEngine({Map<String, String>? merchantMappings}) : merchantMappings = {...?merchantMappings};

  final Map<String, String> merchantMappings;

  static String merchantKey(String? name) =>
      (name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void learn(String merchant, String categoryId, {String? subcategory}) {
    final key = merchantKey(merchant);
    if (key.isEmpty) return;
    merchantMappings[key] = subcategory == null ? categoryId : '$categoryId/$subcategory';
  }

  /// keyword → (category, subcategory)
  static final List<(RegExp, CategoryDef, String?)> _rules = [
    // Income first: "NACH"/"ACH" also appear in EMI auto-debits, so dividend
    // credits must be claimed before the Loan EMI rule below.
    (_r(r'dividend|\bdiv\b|\bint\.? div|\bfin(?:al)? div|nach[\s\-:]*cr|n?ach[\s\-:]*credit|\be?ach[\s\-:]*cr?\b|\bach\s*/|\bn?ach\b'), Categories.investmentReturns, 'Dividend'),
    (_r(r'swiggy|zomato|domino|pizza|kfc|mcdonald|burger|restaurant|cafe|starbucks|eatsure|dining|biryani|bakery|chai|tea'), Categories.food, 'Restaurants'),
    // Local eateries named on card / UPI spends ("KAUSHI FOODS", "Juice", "Sri Krishna Sweets").
    (_r(r'\bfoods?\b|juice|sweets|snacks|bhava?n\b|bhawan|kitchen|dhaba|tiffin|canteen|\bmess\b|ice ?cream|eatery|caterers?'), Categories.food, 'Restaurants'),
    (_r(r'bigbasket|blinkit|zepto|instamart|grofers|dmart|reliance fresh|more retail|jiomart|supermarket|grocer|kirana|nature.?s basket|spencer'), Categories.groceries, 'Groceries'),
    (_r(r'amazon(?!\s*pay)|amazon\s*pay\s*india|flipkart|myntra|ajio|meesho|nykaa|tata ?cliq|croma|reliance digital|decathlon|ikea|lifestyle|shoppers stop|westside|mall|store|mart\b'), Categories.shopping, 'Online shopping'),
    (_r(r'uber|ola\b|olacabs|rapido|metro|irctc|redbus|namma yatri|bmtc|best bus|toll|fastag|parking'), Categories.transportation, 'Commute'),
    (_r(r'petrol|diesel|fuel|hpcl|bpcl|iocl|indian ?oil|bharat petroleum|hindustan petroleum|shell|nayara'), Categories.fuel, 'Fuel'),
    (_r(r'\brent\b|house rent|nobroker|rentpay|landlord'), Categories.rent, 'House rent'),
    (_r(r'maintenance|society|apartment|plumber|electrician|urban ?company|housejoy'), Categories.houseMaintenance, 'Maintenance'),
    (_r(r'electricity|bescom|tneb|tangedco|msedcl|bses|tata power|adani electricity|cesc|power bill|torrent power|kseb'), Categories.electricity, 'Electricity'),
    (_r(r'water bill|water board|jal board|bwssb|cmwssb'), Categories.water, 'Water'),
    // TV / DTH before Mobile, so "Airtel DTH" isn't a phone recharge; Tata Play Fiber stays Internet.
    (_r(r'tata ?play(?!\s*fiber)|tata ?sky|dish ?tv|\bd2h\b|sun direct|airtel (?:dth|digital tv)|\bdth\b'), Categories.subscription, 'TV / DTH'),
    (_r(r'recharge|prepaid|postpaid|airtel|jio|vodafone|\bvi\b|bsnl'), Categories.mobile, 'Mobile'),
    (_r(r'broadband|fibernet|act fiber|hathway|internet|excitel|tata play fiber|wifi'), Categories.internet, 'Broadband'),
    (_r(r'hospital|clinic|apollo|fortis|manipal|diagnostic|lab|\bdr\. |doctor|dental|health|practo'), Categories.healthcare, 'Medical'),
    (_r(r'pharma|pharmacy|medical store|medicals?\b|1mg|pharmeasy|netmeds|medplus|chemist|medicine|drug ?house'), Categories.medicines, 'Pharmacy'),
    (_r(r'school|college|university|tuition|udemy|coursera|byju|unacademy|fees|education|exam'), Categories.education, 'Education'),
    (_r(r'netflix|hotstar|spotify|prime video|youtube premium|apple\.com|icloud|google one|zee5|sonyliv|jiocinema|subscription|renewal|chatgpt|openai|adobe|microsoft 365'), Categories.subscription, 'Digital subscription'),
    (_r(r'bookmyshow|pvr|inox|cinema|movie|gaming|steam|playstation|concert|wonderla'), Categories.entertainment, 'Movies & events'),
    (_r(r'makemytrip|goibibo|cleartrip|yatra|indigo|air india|vistara|spicejet|akasa|airline|airport|ixigo|easemytrip'), Categories.travel, 'Flights & trips'),
    (_r(r'oyo|hotel|resort|airbnb|treebo|fabhotel|taj|marriott|hyatt|booking\.com|agoda'), Categories.hotel, 'Stay'),
    (_r(r'\blic\b|insurance|policybazaar|premium|hdfc life|icici pru|star health|acko|digit insurance|max life|bajaj allianz'), Categories.insurance, 'Insurance premium'),
    (_r(r'\bsip\b|mutual fund|\bmf\b|zerodha|groww|upstox|kuvera|smallcase|\bnps\b|\bppf\b|\belss\b|angel one|paytm money|indmoney|et money'), Categories.investments, 'SIP / mutual fund'),
    (_r(r'\bemi\b|loan|bajaj ?finance|home credit|nach|ecs|\be?ach[\s\-:]*d(?:r|ebit)?\b'), Categories.loanEmi, 'Loan EMI'),
    (_r(r'charges|charge|fee\b|fees|gst on|sms alert|annual fee|penalty|late payment|amc'), Categories.bankCharges, 'Bank charges'),
    (_r(r'dividend|mutual fund|redemption|zerodha|groww|upstox|kuvera|coin|nse|bse'), Categories.investmentReturns, 'Investments'),
  ];

  static RegExp _r(String p) => RegExp(p, caseSensitive: false);

  CategorizationResult categorize(CategorizationInput input) {
    // 1. Learned merchant mappings win.
    for (final name in [input.merchant, input.counterparty]) {
      final mapped = merchantMappings[merchantKey(name)];
      if (mapped != null) {
        final parts = mapped.split('/');
        return CategorizationResult(Categories.byId(parts.first), parts.length > 1 ? parts[1] : null, 1.0, matchedBy: 'merchant-mapping');
      }
    }

    // 2. Strong signals from the transaction type.
    final typed = _byType(input);
    if (typed != null) return typed;

    final haystack = [input.merchant, input.counterparty, input.narration, input.upiId].whereType<String>().join(' ');

    // 3. Keyword rules.
    for (final (re, cat, sub) in _rules) {
      if (!re.hasMatch(haystack)) continue;
      if (cat.isIncome != (input.direction == TxDirection.inflow)) {
        // An inflow from "Amazon" is most likely a refund.
        if (input.direction == TxDirection.inflow && !cat.isIncome) {
          return CategorizationResult(Categories.refund, 'Merchant credit', 0.6, matchedBy: 'keyword-inflow');
        }
        continue;
      }
      final strong = input.merchant != null && re.hasMatch(input.merchant!);
      return CategorizationResult(cat, sub, strong ? 0.85 : 0.7, matchedBy: 'keyword');
    }

    // 4. Person-to-person heuristics.
    if (input.direction == TxDirection.outflow && _looksLikePerson(input)) {
      return const CategorizationResult(Categories.personalTransfer, 'Friends & family', 0.6, matchedBy: 'p2p');
    }
    if (input.direction == TxDirection.inflow) {
      if (input.paymentMode == PaymentMode.neft || input.paymentMode == PaymentMode.rtgs) {
        return const CategorizationResult(Categories.otherIncome, 'Bank transfer', 0.5, needsReview: true, matchedBy: 'fallback');
      }
      return const CategorizationResult(Categories.otherIncome, null, 0.4, needsReview: true, matchedBy: 'fallback');
    }
    return const CategorizationResult(Categories.others, null, 0.2, needsReview: true, matchedBy: 'fallback');
  }

  CategorizationResult? _byType(CategorizationInput i) => switch (i.type) {
        TxType.salaryCredit => const CategorizationResult(Categories.salary, 'Monthly salary', 0.95, matchedBy: 'type'),
        TxType.interestCredit => const CategorizationResult(Categories.interest, 'Savings interest', 0.95, matchedBy: 'type'),
        TxType.refund || TxType.reversed => const CategorizationResult(Categories.refund, null, 0.9, matchedBy: 'type'),
        TxType.cashDeposit => const CategorizationResult(Categories.cashDeposit, null, 0.9, matchedBy: 'type'),
        TxType.atmWithdrawal => const CategorizationResult(Categories.atm, 'Cash withdrawal', 0.95, matchedBy: 'type'),
        TxType.emiDebit => const CategorizationResult(Categories.loanEmi, 'Loan EMI', 0.9, matchedBy: 'type'),
        TxType.creditCardBillPayment when i.direction == TxDirection.outflow =>
          const CategorizationResult(Categories.creditCardPayment, 'Card bill', 0.9, matchedBy: 'type'),
        _ => null,
      };

  bool _looksLikePerson(CategorizationInput i) {
    if (i.paymentMode != PaymentMode.upi && i.paymentMode != PaymentMode.imps && i.paymentMode != PaymentMode.neft) {
      return false;
    }
    final upi = i.upiId ?? '';
    if (RegExp(r'^\d{10}@').hasMatch(upi)) return true;
    final name = (i.counterparty ?? '').trim();
    if (name.isEmpty) return false;
    final words = name.split(RegExp(r'\s+'));
    final businessy = RegExp(r'(pvt|ltd|llp|limited|enterprises|store|services|technologies|traders|retail|india|payments|merchant)',
        caseSensitive: false);
    return words.length >= 2 && words.length <= 4 && !businessy.hasMatch(name);
  }
}
