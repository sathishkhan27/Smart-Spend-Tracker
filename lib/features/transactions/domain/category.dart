/// Static category catalog. Icons are referenced by key and resolved in the
/// presentation layer so the domain stays Flutter-agnostic.
class CategoryDef {
  const CategoryDef(this.id, this.name, {required this.isIncome, required this.iconKey, required this.colorValue, this.group});

  final String id;
  final String name;
  final bool isIncome;
  final String iconKey;
  final int colorValue;

  /// Dashboard roll-up bucket (e.g. "Bills" groups electricity, water, internet).
  final String? group;
}

abstract final class Categories {
  // Income
  static const salary = CategoryDef('salary', 'Salary', isIncome: true, iconKey: 'salary', colorValue: 0xFF16A36A, group: 'Salary');
  static const business = CategoryDef('business_income', 'Business Income', isIncome: true, iconKey: 'business', colorValue: 0xFF0EA5E9, group: 'Business Income');
  static const interest = CategoryDef('interest', 'Interest', isIncome: true, iconKey: 'interest', colorValue: 0xFF14B8A6, group: 'Interest');
  static const refund = CategoryDef('refund', 'Refund', isIncome: true, iconKey: 'refund', colorValue: 0xFF8B5CF6, group: 'Refund');
  static const cashDeposit = CategoryDef('cash_deposit', 'Cash Deposit', isIncome: true, iconKey: 'cash', colorValue: 0xFF64748B, group: 'Other Credits');
  static const investmentReturns = CategoryDef('investment_returns', 'Investment Returns', isIncome: true, iconKey: 'investment', colorValue: 0xFFF2A93B, group: 'Other Credits');
  static const otherIncome = CategoryDef('other_income', 'Other Income', isIncome: true, iconKey: 'income', colorValue: 0xFF22C55E, group: 'Other Credits');

  // Expense
  static const food = CategoryDef('food_dining', 'Food & Dining', isIncome: false, iconKey: 'food', colorValue: 0xFFF97316, group: 'Food');
  static const shopping = CategoryDef('shopping', 'Shopping', isIncome: false, iconKey: 'shopping', colorValue: 0xFFEC4899, group: 'Shopping');
  static const groceries = CategoryDef('groceries', 'Groceries', isIncome: false, iconKey: 'groceries', colorValue: 0xFF84CC16, group: 'Food');
  static const transportation = CategoryDef('transportation', 'Transportation', isIncome: false, iconKey: 'transport', colorValue: 0xFF0EA5E9, group: 'Travel');
  static const fuel = CategoryDef('fuel', 'Fuel', isIncome: false, iconKey: 'fuel', colorValue: 0xFFEF4444, group: 'Travel');
  static const rent = CategoryDef('rent', 'Rent', isIncome: false, iconKey: 'rent', colorValue: 0xFF6366F1, group: 'Bills');
  static const houseMaintenance = CategoryDef('house_maintenance', 'House Maintenance', isIncome: false, iconKey: 'maintenance', colorValue: 0xFFA16207, group: 'Bills');
  static const electricity = CategoryDef('electricity', 'Electricity', isIncome: false, iconKey: 'electricity', colorValue: 0xFFEAB308, group: 'Bills');
  static const water = CategoryDef('water_bill', 'Water Bill', isIncome: false, iconKey: 'water', colorValue: 0xFF06B6D4, group: 'Bills');
  static const mobile = CategoryDef('mobile_recharge', 'Mobile Recharge', isIncome: false, iconKey: 'mobile', colorValue: 0xFF3B82F6, group: 'Bills');
  static const internet = CategoryDef('internet', 'Internet', isIncome: false, iconKey: 'internet', colorValue: 0xFF2563EB, group: 'Bills');
  static const healthcare = CategoryDef('healthcare', 'Healthcare', isIncome: false, iconKey: 'health', colorValue: 0xFFDC2626, group: 'Healthcare');
  static const medicines = CategoryDef('medicines', 'Medicines', isIncome: false, iconKey: 'medicine', colorValue: 0xFFF43F5E, group: 'Healthcare');
  static const education = CategoryDef('education', 'Education', isIncome: false, iconKey: 'education', colorValue: 0xFF7C3AED, group: 'Other Expenses');
  static const entertainment = CategoryDef('entertainment', 'Entertainment', isIncome: false, iconKey: 'entertainment', colorValue: 0xFFD946EF, group: 'Other Expenses');
  static const travel = CategoryDef('travel', 'Travel', isIncome: false, iconKey: 'travel', colorValue: 0xFF0891B2, group: 'Travel');
  static const hotel = CategoryDef('hotel', 'Hotel', isIncome: false, iconKey: 'hotel', colorValue: 0xFF9333EA, group: 'Travel');
  static const loanEmi = CategoryDef('loan_emi', 'Loan EMI', isIncome: false, iconKey: 'emi', colorValue: 0xFF142B4A, group: 'EMI');
  static const creditCardPayment = CategoryDef('credit_card_payment', 'Credit Card Payment', isIncome: false, iconKey: 'card', colorValue: 0xFF334155, group: 'Bills');
  static const insurance = CategoryDef('insurance', 'Insurance', isIncome: false, iconKey: 'insurance', colorValue: 0xFF0F766E, group: 'Bills');
  static const subscription = CategoryDef('subscription', 'Subscription', isIncome: false, iconKey: 'subscription', colorValue: 0xFFE11D48, group: 'Bills');
  /// Money moved into SIPs, mutual funds, stocks, NPS… (an outflow, not spending on goods).
  static const investments = CategoryDef('investments', 'Investments / SIP', isIncome: false, iconKey: 'investment', colorValue: 0xFF16A34A, group: 'Other Expenses');
  static const atm = CategoryDef('atm_withdrawal', 'ATM Withdrawal', isIncome: false, iconKey: 'atm', colorValue: 0xFF475569, group: 'Other Expenses');
  static const bankCharges = CategoryDef('bank_charges', 'Bank Charges', isIncome: false, iconKey: 'bank', colorValue: 0xFF78716C, group: 'Other Expenses');
  static const personalTransfer = CategoryDef('personal_transfer', 'Personal Transfer', isIncome: false, iconKey: 'transfer', colorValue: 0xFF3478F6, group: 'Other Expenses');
  static const others = CategoryDef('others', 'Others', isIncome: false, iconKey: 'others', colorValue: 0xFF94A3B8, group: 'Other Expenses');

  static const income = [salary, business, interest, refund, cashDeposit, investmentReturns, otherIncome];
  static const expense = [
    food, shopping, groceries, transportation, fuel, rent, houseMaintenance, electricity, water, mobile,
    internet, healthcare, medicines, education, entertainment, travel, hotel, loanEmi, creditCardPayment,
    insurance, subscription, investments, atm, bankCharges, personalTransfer, others,
  ];
  static const all = [...income, ...expense];

  static const incomeGroups = ['Salary', 'Business Income', 'Refund', 'Interest', 'Other Credits'];
  static const expenseGroups = ['Food', 'Shopping', 'Travel', 'Bills', 'EMI', 'Healthcare', 'Other Expenses'];

  static final Map<String, CategoryDef> _byId = {for (final c in all) c.id: c};

  static CategoryDef byId(String? id) => _byId[id] ?? others;
}
