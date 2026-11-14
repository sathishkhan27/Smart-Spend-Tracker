import 'package:flutter/material.dart';

/// Brand palette for Smart Spend Tracker.
abstract final class AppColors {
  static const navy = Color(0xFF142B4A);
  static const navyLight = Color(0xFF1F3D66);
  static const blue = Color(0xFF3478F6);
  static const mint = Color(0xFF4ADEA0);
  static const income = Color(0xFF16A36A);
  static const expense = Color(0xFFE05252);
  static const warning = Color(0xFFF2A93B);
  static const background = Color(0xFFF6F8FC);
  static const card = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF7B8495);
  static const textPrimary = Color(0xFF14213D);
  static const divider = Color(0xFFE7EBF3);

  // Dark theme surfaces.
  static const darkBackground = Color(0xFF0B1424);
  static const darkCard = Color(0xFF14213A);
  static const darkDivider = Color(0xFF22324F);

  static const heroGradient = LinearGradient(
    colors: [navy, Color(0xFF234C85), blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0, 0.6, 1],
  );

  // ---- Chart colors (validated for color-vision deficiency) ----
  // Green/red fails CVD separation (deutan ΔE 4.5), so charts encode
  // income/expense with a validated blue/orange pair plus legends.
  static const chartIncome = Color(0xFF2A78D6);
  static const chartExpense = Color(0xFFEB6834);
  static const chartIncomeDark = Color(0xFF3987E5);
  static const chartExpenseDark = Color(0xFFD95926);

  /// Categorical slots, assigned in fixed order — never cycled.
  static const chartPalette = <Color>[
    Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100),
    Color(0xFFE87BA4), Color(0xFF008300), Color(0xFF6250D6), Color(0xFFE34948),
  ];
  static const chartPaletteDark = <Color>[
    Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500),
    Color(0xFFD55181), Color(0xFF008300), Color(0xFF9085E9), Color(0xFFE66767),
  ];
}
