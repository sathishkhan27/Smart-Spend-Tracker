import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Brand mark: the wallet app icon (assets/brand/logo.png), shown as a
/// rounded tile. Launcher icons are generated from the same source by
/// tool/make_icons.py.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44, this.shadow = true});
  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.24),
          boxShadow: shadow
              ? [BoxShadow(color: AppColors.navy.withValues(alpha: 0.18), blurRadius: size * 0.3, offset: Offset(0, size * 0.1))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          // Decode at display size instead of the full 512px asset.
          child: Image.asset(
            'assets/brand/logo.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
      );
}

/// Logo + "Smart Spend" wordmark (optional "TRACKER" tagline).
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.logoSize = 40, this.light = false, this.tagline = true, this.fontSize = 19});
  final double logoSize;
  final bool light;
  final bool tagline;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final main = light ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.navy);
    final accent = light ? AppColors.mint : AppColors.blue;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppLogo(size: logoSize),
      SizedBox(width: logoSize * 0.28),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Smart', style: TextStyle(color: main)),
            TextSpan(text: 'Spend', style: TextStyle(color: accent)),
          ]),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.1),
        ),
        if (tagline)
          Text(
            'TRACKER',
            style: TextStyle(
              fontSize: fontSize * 0.5,
              fontWeight: FontWeight.w600,
              letterSpacing: fontSize * 0.22,
              color: main.withValues(alpha: 0.6),
              height: 1.3,
            ),
          ),
      ]),
    ]);
  }
}
