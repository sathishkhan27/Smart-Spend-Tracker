import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Branded page backdrop: a soft vertical gradient with blurred brand-colour
/// glows and faint rings in the top-right corner. Static and cheap to paint.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(
        child: RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(dark: dark))),
      ),
      child,
    ]);
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.dark});
  final bool dark;

  static const _violet = Color(0xFF8B7CF6);
  static const _peach = Color(0xFFFFB38A);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final unit = math.min(w, 520.0);

    // 1. Base wash.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF13254A), Color(0xFF0D1830), AppColors.darkBackground]
              : const [Color(0xFFDFE9FE), Color(0xFFF1F5FD), Color(0xFFF7F8FC)],
          stops: const [0, 0.38, 1],
        ).createShader(rect),
    );

    // 2. Mesh glows.
    void glow(Offset c, double r, Color color, double alpha) => canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: r)),
        );
    glow(Offset(w * 1.0, -unit * 0.1), unit * 1.0, AppColors.blue, dark ? 0.38 : 0.30);
    glow(Offset(w * 0.25, -unit * 0.15), unit * 0.75, _violet, dark ? 0.16 : 0.14);
    glow(Offset(-unit * 0.15, h * 0.30), unit * 0.70, AppColors.mint, dark ? 0.10 : 0.16);
    glow(Offset(w * 1.05, h * 0.72), unit * 0.75, dark ? _violet : _peach, dark ? 0.10 : 0.12);
    glow(Offset(w * 0.0, h * 1.02), unit * 0.95, AppColors.blue, dark ? 0.14 : 0.08);

    // 3. Layered translucent waves across the top.
    final waveTop = h * 0.30;
    for (final (i, alpha) in const [(0, 0.55), (1, 0.35)]) {
      final y = waveTop - i * unit * 0.07;
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(w * 0.28, y - unit * 0.16, w * 0.62, y + unit * 0.12, w, y - unit * 0.10)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [AppColors.darkBackground.withValues(alpha: alpha * 0.9), AppColors.darkBackground.withValues(alpha: alpha)]
                : [Colors.white.withValues(alpha: alpha * 0.55), const Color(0xFFF7F8FC).withValues(alpha: alpha)],
          ).createShader(Rect.fromLTWH(0, y - unit * 0.2, w, h)),
      );
      // Highlight line along the crest.
      final crest = Path()
        ..moveTo(0, y)
        ..cubicTo(w * 0.28, y - unit * 0.16, w * 0.62, y + unit * 0.12, w, y - unit * 0.10);
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = LinearGradient(colors: [
            (dark ? Colors.white : AppColors.blue).withValues(alpha: 0),
            (dark ? Colors.white : AppColors.blue).withValues(alpha: dark ? 0.10 : 0.16),
            (dark ? Colors.white : AppColors.blue).withValues(alpha: 0),
          ]).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }

    // 4. Dot grid fading out from the top-right corner.
    final dot = Paint();
    const gap = 18.0;
    final reach = unit * 0.62;
    final corner = Offset(w, 0);
    for (var x = w - gap / 2; x > w - reach; x -= gap) {
      for (var y = gap / 2; y < reach; y += gap) {
        final d = (Offset(x, y) - corner).distance / reach;
        if (d >= 1) continue;
        dot.color = (dark ? Colors.white : AppColors.navy).withValues(alpha: (1 - d) * (dark ? 0.10 : 0.09));
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }

    // 5. Faint concentric rings.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (dark ? Colors.white : AppColors.blue).withValues(alpha: dark ? 0.05 : 0.07);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(Offset(-unit * 0.05, h * 0.62), unit * 0.14 * i, ring);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.dark != dark;
}

/// Wraps the platform's page transition so every route carries its own
/// [AppBackground] (pages stay opaque while sliding over each other).
class BackgroundPageTransitionsBuilder extends PageTransitionsBuilder {
  const BackgroundPageTransitionsBuilder(this.inner);
  final PageTransitionsBuilder inner;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => inner.delegatedTransition;
  @override
  Duration get transitionDuration => inner.transitionDuration;
  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      inner.buildTransitions(route, context, animation, secondaryAnimation, AppBackground(child: child));
}

/// Frosted strip for the one header that floats over scrolling content
/// (Activity filters); it matches the page tone instead of a solid colour.
class FrostedBar extends StatelessWidget {
  const FrostedBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: ColoredBox(
          color: (dark ? AppColors.darkBackground : const Color(0xFFF1F5FD)).withValues(alpha: 0.82),
          child: child,
        ),
      ),
    );
  }
}
