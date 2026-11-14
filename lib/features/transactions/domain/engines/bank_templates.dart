/// Configurable bank / institution templates for the parsing engine.
///
/// Templates can be shipped with the app ([defaultTemplates]) and extended at
/// runtime from Firestore `transaction_rules` documents via [BankTemplate.fromJson].
class BankTemplate {
  const BankTemplate({
    required this.id,
    required this.name,
    this.smsSenderCodes = const [],
    this.emailDomains = const [],
    this.bodyKeywords = const [],
    this.patterns = const [],
    this.kind = InstitutionKind.bank,
  });

  factory BankTemplate.fromJson(Map<String, dynamic> j) => BankTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: InstitutionKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => InstitutionKind.bank),
        smsSenderCodes: List<String>.from(j['smsSenderCodes'] ?? const []),
        emailDomains: List<String>.from(j['emailDomains'] ?? const []),
        bodyKeywords: List<String>.from(j['bodyKeywords'] ?? const []),
        patterns: [
          for (final p in (j['patterns'] as List? ?? const []))
            TemplatePattern(p['regex'] as String, direction: p['direction'] as String?),
        ],
      );

  final String id;
  final String name;
  final InstitutionKind kind;

  /// DLT header fragments, e.g. "HDFCBK" matches "VM-HDFCBK" and "AD-HDFCBK-S".
  final List<String> smsSenderCodes;
  final List<String> emailDomains;

  /// Lower-case fragments that identify the institution in a message body.
  final List<String> bodyKeywords;

  /// Bank-specific regexes using named groups: amount, account, merchant, date, ref.
  final List<TemplatePattern> patterns;

  bool matchesSender(String sender) {
    final s = sender.toUpperCase();
    return smsSenderCodes.any((c) => s.contains(c));
  }

  bool matchesEmail(String email) {
    final e = email.toLowerCase();
    return emailDomains.any((d) => e.endsWith('@$d') || e.endsWith('.$d'));
  }

  bool matchesBody(String lowerBody) => bodyKeywords.any(lowerBody.contains);
}

enum InstitutionKind { bank, creditCard, upiApp, wallet, paymentGateway, lender, merchant }

class TemplatePattern {
  const TemplatePattern(this.regex, {this.direction});
  final String regex;

  /// Optional forced direction: "inflow" / "outflow".
  final String? direction;
}

const defaultTemplates = <BankTemplate>[
  BankTemplate(
    id: 'hdfc',
    name: 'HDFC Bank',
    smsSenderCodes: ['HDFCBK', 'HDFCBN'],
    emailDomains: ['hdfcbank.net', 'hdfcbank.com'],
    bodyKeywords: ['hdfc bank', 'hdfcbank'],
    patterns: [
      TemplatePattern(
          r'(?:rs\.?|inr)\s*(?<amount>[\d,]+(?:\.\d{1,2})?)\s+debited from a/c\s*\*{0,}x*(?<account>\d{3,6})\s+on\s+(?<date>\d{2}[-/]\d{2}[-/]\d{2,4})\s+to\s+(?:vpa\s+)?(?<merchant>[^\(\n]+?)\s*(?:\(upi\s*ref\s*no\.?\s*(?<ref>\d{8,}))',
          direction: 'outflow'),
    ],
  ),
  BankTemplate(
    id: 'sbi',
    name: 'State Bank of India',
    smsSenderCodes: ['SBIINB', 'SBIUPI', 'SBIPSG', 'SBMSMS', 'ATMSBI', 'CBSSBI', 'SBICRD'],
    emailDomains: ['sbi.co.in', 'onlinesbi.com', 'sbicard.com'],
    bodyKeywords: ['sbi', 'state bank'],
    patterns: [
      TemplatePattern(
          r'a/c\s*x*(?<account>\d{3,6})\s+debited by\s*(?<amount>[\d,]+(?:\.\d{1,2})?)\s+on date\s+(?<date>\d{1,2}[a-z]{3}\d{2,4})\s+trf to\s+(?<merchant>.+?)\s+refno\s+(?<ref>\d{8,})',
          direction: 'outflow'),
    ],
  ),
  BankTemplate(
    id: 'icici',
    name: 'ICICI Bank',
    smsSenderCodes: ['ICICIB', 'ICICIT'],
    emailDomains: ['icicibank.com'],
    bodyKeywords: ['icici bank', 'icici'],
  ),
  BankTemplate(
    id: 'axis',
    name: 'Axis Bank',
    smsSenderCodes: ['AXISBK', 'AXISMR'],
    emailDomains: ['axisbank.com'],
    bodyKeywords: ['axis bank'],
  ),
  BankTemplate(
    id: 'kotak',
    name: 'Kotak Mahindra Bank',
    smsSenderCodes: ['KOTAKB', 'KMBANK'],
    emailDomains: ['kotak.com'],
    bodyKeywords: ['kotak'],
  ),
  BankTemplate(id: 'yes', name: 'Yes Bank', smsSenderCodes: ['YESBNK'], emailDomains: ['yesbank.in'], bodyKeywords: ['yes bank']),
  BankTemplate(id: 'idfc', name: 'IDFC FIRST Bank', smsSenderCodes: ['IDFCFB'], emailDomains: ['idfcfirstbank.com'], bodyKeywords: ['idfc first']),
  BankTemplate(id: 'indusind', name: 'IndusInd Bank', smsSenderCodes: ['INDUSB', 'IBLBNK'], emailDomains: ['indusind.com'], bodyKeywords: ['indusind']),
  BankTemplate(id: 'pnb', name: 'Punjab National Bank', smsSenderCodes: ['PNBSMS', 'PUNBNK'], emailDomains: ['pnb.co.in'], bodyKeywords: ['pnb', 'punjab national']),
  BankTemplate(id: 'bob', name: 'Bank of Baroda', smsSenderCodes: ['BOBTXN', 'BOBSMS'], emailDomains: ['bankofbaroda.com', 'bankofbaroda.co.in'], bodyKeywords: ['bank of baroda']),
  BankTemplate(id: 'canara', name: 'Canara Bank', smsSenderCodes: ['CANBNK'], emailDomains: ['canarabank.com'], bodyKeywords: ['canara bank']),
  BankTemplate(id: 'union', name: 'Union Bank of India', smsSenderCodes: ['UNIONB'], emailDomains: ['unionbankofindia.bank'], bodyKeywords: ['union bank']),
  BankTemplate(id: 'iob', name: 'Indian Overseas Bank', smsSenderCodes: ['IOBCHN', 'IOBBNK'], emailDomains: ['iob.in'], bodyKeywords: ['indian overseas bank', 'iob']),
  BankTemplate(id: 'indian', name: 'Indian Bank', smsSenderCodes: ['INDBNK'], emailDomains: ['indianbank.co.in'], bodyKeywords: ['indian bank']),
  BankTemplate(id: 'federal', name: 'Federal Bank', smsSenderCodes: ['FEDBNK'], emailDomains: ['federalbank.co.in'], bodyKeywords: ['federal bank']),
  BankTemplate(id: 'amex', name: 'American Express', kind: InstitutionKind.creditCard, smsSenderCodes: ['AMEXIN'], emailDomains: ['americanexpress.com', 'aexp.com'], bodyKeywords: ['american express', 'amex']),
  BankTemplate(id: 'paytm', name: 'Paytm Payments Bank', kind: InstitutionKind.wallet, smsSenderCodes: ['PAYTMB', 'iPaytm', 'PYTMBK'], emailDomains: ['paytm.com', 'paytmbank.com'], bodyKeywords: ['paytm']),
  BankTemplate(id: 'phonepe', name: 'PhonePe', kind: InstitutionKind.upiApp, smsSenderCodes: ['PHONPE'], emailDomains: ['phonepe.com'], bodyKeywords: ['phonepe']),
  BankTemplate(id: 'gpay', name: 'Google Pay', kind: InstitutionKind.upiApp, smsSenderCodes: ['GPAY'], emailDomains: ['google.com'], bodyKeywords: ['google pay']),
  BankTemplate(id: 'amazonpay', name: 'Amazon Pay', kind: InstitutionKind.wallet, smsSenderCodes: ['AMZPAY', 'AMAZON'], emailDomains: ['amazonpay.in'], bodyKeywords: ['amazon pay']),
  BankTemplate(id: 'razorpay', name: 'Razorpay', kind: InstitutionKind.paymentGateway, smsSenderCodes: ['RZRPAY'], emailDomains: ['razorpay.com'], bodyKeywords: ['razorpay']),
  BankTemplate(id: 'bajaj', name: 'Bajaj Finance', kind: InstitutionKind.lender, smsSenderCodes: ['BAJAJF', 'BAJFIN'], emailDomains: ['bajajfinserv.in'], bodyKeywords: ['bajaj finance', 'bajaj finserv']),
];
