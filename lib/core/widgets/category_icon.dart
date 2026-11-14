import 'package:flutter/material.dart';

import '../../features/transactions/domain/category.dart';
import '../../features/transactions/domain/transaction_enums.dart';

abstract final class CategoryIcons {
  static const _icons = <String, IconData>{
    'salary': Icons.work_outline_rounded,
    'business': Icons.storefront_outlined,
    'interest': Icons.savings_outlined,
    'refund': Icons.replay_circle_filled_outlined,
    'cash': Icons.payments_outlined,
    'investment': Icons.trending_up_rounded,
    'income': Icons.south_west_rounded,
    'food': Icons.restaurant_rounded,
    'shopping': Icons.shopping_bag_outlined,
    'groceries': Icons.local_grocery_store_outlined,
    'transport': Icons.directions_car_filled_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'rent': Icons.home_outlined,
    'maintenance': Icons.handyman_outlined,
    'electricity': Icons.bolt_rounded,
    'water': Icons.water_drop_outlined,
    'mobile': Icons.smartphone_rounded,
    'internet': Icons.wifi_rounded,
    'health': Icons.local_hospital_outlined,
    'medicine': Icons.medication_outlined,
    'education': Icons.school_outlined,
    'entertainment': Icons.movie_outlined,
    'travel': Icons.flight_takeoff_rounded,
    'hotel': Icons.hotel_outlined,
    'emi': Icons.account_balance_outlined,
    'card': Icons.credit_card_rounded,
    'insurance': Icons.shield_outlined,
    'subscription': Icons.autorenew_rounded,
    'atm': Icons.local_atm_rounded,
    'bank': Icons.receipt_long_outlined,
    'transfer': Icons.swap_horiz_rounded,
    'others': Icons.category_outlined,
  };

  static IconData of(String key) => _icons[key] ?? Icons.category_outlined;

  static IconData paymentMode(PaymentMode m) => switch (m) {
        PaymentMode.upi => Icons.qr_code_2_rounded,
        PaymentMode.neft || PaymentMode.imps || PaymentMode.rtgs || PaymentMode.netBanking => Icons.account_balance_rounded,
        PaymentMode.debitCard || PaymentMode.creditCard => Icons.credit_card_rounded,
        PaymentMode.atm || PaymentMode.cash => Icons.payments_rounded,
        PaymentMode.wallet => Icons.account_balance_wallet_rounded,
        PaymentMode.autoDebit => Icons.autorenew_rounded,
        PaymentMode.cheque => Icons.description_outlined,
        PaymentMode.other => Icons.more_horiz_rounded,
      };
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 44});
  final CategoryDef category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(CategoryIcons.of(category.iconKey), color: color, size: size * 0.5),
    );
  }
}
