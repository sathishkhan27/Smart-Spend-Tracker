import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/app_background.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static const radius = 20.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: brightness,
      primary: isDark ? AppColors.blue : AppColors.navy,
      secondary: AppColors.blue,
      error: AppColors.expense,
      surface: isDark ? AppColors.darkCard : AppColors.card,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: isDark ? Colors.white : AppColors.textPrimary,
      displayColor: isDark ? Colors.white : AppColors.textPrimary,
    );

    return base.copyWith(
      // Pages are transparent; AppBackground (via the page transitions) paints behind them.
      scaffoldBackgroundColor: Colors.transparent,

      textTheme: textTheme.copyWith(
        headlineMedium: textTheme.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineSmall: textTheme.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
        titleSmall: textTheme.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 13.5),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12),
        labelSmall: textTheme.labelSmall?.copyWith(fontSize: 10.5, letterSpacing: 0.1),
      ),
      // Transparent top bar: it blends into the page background (AppBackground).
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkDivider : AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCard : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? AppColors.blue : AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: isDark ? AppColors.darkDivider : AppColors.divider),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        indicatorColor: AppColors.blue.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: BackgroundPageTransitionsBuilder(FadeForwardsPageTransitionsBuilder()),
        TargetPlatform.iOS: BackgroundPageTransitionsBuilder(CupertinoPageTransitionsBuilder()),
      }),
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get secondaryText => isDark ? Colors.white60 : AppColors.textSecondary;
  Color get cardColor => isDark ? AppColors.darkCard : AppColors.card;
}
