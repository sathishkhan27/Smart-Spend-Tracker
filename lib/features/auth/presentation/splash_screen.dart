import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common.dart';

/// Animated launch screen. Starts on the same navy as the native Android
/// splash (no flash), then the aurora backdrop, orbiting rings, logo and
/// wordmark animate in. Motion stops when the OS asks to reduce it.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  /// One-shot entrance (logo, text, footer).
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  /// Continuous drift / rotation of the backdrop and orbits.
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  /// Ripple pulse from the logo.
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _loop.stop();
      _pulse.stop();
    } else {
      if (!_intro.isAnimating && _intro.value == 0) _intro.forward();
      if (!_loop.isAnimating) _loop.repeat();
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Animation<double> _phase(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final bg = _phase(0, 0.45, Curves.easeOut);
    final logo = _phase(0.08, 0.5, Curves.easeOutBack);
    final title = _phase(0.3, 0.7);
    final tagline = _phase(0.45, 0.85);
    final footer = _phase(0.6, 1);

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(fit: StackFit.expand, children: [
        // Backdrop fades in over the native-splash navy.
        FadeTransition(
          opacity: bg,
          child: RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(_loop))),
        ),
        SafeArea(
          child: Column(children: [
            const Spacer(flex: 5),
            // Logo with orbit rings and ripples.
            SizedBox(
              width: 280,
              height: 280,
              child: Stack(alignment: Alignment.center, children: [
                FadeTransition(
                  opacity: bg,
                  child: RepaintBoundary(child: CustomPaint(size: const Size(280, 280), painter: _OrbitPainter(_loop, _pulse))),
                ),
                FadeTransition(
                  opacity: logo,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.6, end: 1.0).animate(logo),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.55), blurRadius: 60, spreadRadius: 6)],
                      ),
                      child: const AppLogo(size: 104, shadow: false),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            _SlideFade(
              animation: title,
              child: Text.rich(
                const TextSpan(children: [
                  TextSpan(text: 'Smart'),
                  TextSpan(text: 'Spend', style: TextStyle(color: AppColors.mint)),
                ]),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            _SlideFade(
              animation: tagline,
              child: Column(children: [
                // Tagline letter-spacing eases open as it appears.
                AnimatedBuilder(
                  animation: tagline,
                  builder: (_, __) => Text(
                    'TRACKER',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2 + 4 * tagline.value,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Your money, understood automatically',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5, fontWeight: FontWeight.w500)),
              ]),
            ),
            const Spacer(flex: 6),
            FadeTransition(
              opacity: footer,
              child: Column(children: [
                _ShimmerBar(animation: _pulse),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_rounded, size: 13, color: Colors.white.withValues(alpha: 0.55)),
                  const SizedBox(width: 6),
                  Text('Private  •  Secure  •  Automatic',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                ]),
                const SizedBox(height: 22),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SlideFade extends StatelessWidget {
  const _SlideFade({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(animation),
          child: child,
        ),
      );
}

/// Slim indeterminate loader: a mint highlight sweeping across a glass track.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, __) => CustomPaint(painter: _ShimmerPainter(animation.value)),
          ),
        ),
      );
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.14));
    final w = size.width * 0.45;
    final x = -w + (size.width + w) * Curves.easeInOut.transform(t);
    final rect = Rect.fromLTWH(x, 0, w, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          AppColors.mint.withValues(alpha: 0),
          AppColors.mint,
          AppColors.mint.withValues(alpha: 0),
        ]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

/// Navy→blue gradient with drifting aurora glows, a fine dot grid and
/// sparkles that float upwards.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static const _violet = Color(0xFF7C5CFF);
  static const _cyan = Color(0xFF00C2FF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final a = t.value * 2 * math.pi;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1A33), AppColors.navy, Color(0xFF1C3F86), Color(0xFF2A5FCB)],
          stops: [0, 0.35, 0.75, 1],
        ).createShader(rect),
    );

    void glow(Offset c, double r, Color color, double alpha) => canvas.drawCircle(
          c,
          r,
          Paint()..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
        );
    final u = math.min(w, h);
    glow(Offset(w * (0.85 + 0.08 * math.cos(a)), h * (0.12 + 0.05 * math.sin(a))), u * 0.75, AppColors.blue, 0.55);
    glow(Offset(w * (0.1 + 0.08 * math.sin(a + 1)), h * (0.32 + 0.06 * math.cos(a))), u * 0.6, _violet, 0.32);
    glow(Offset(w * (0.25 + 0.1 * math.cos(a + 2)), h * (0.9 + 0.04 * math.sin(a * 2))), u * 0.7, AppColors.mint, 0.22);
    glow(Offset(w * (0.95 + 0.05 * math.sin(a + 3)), h * (0.78 + 0.05 * math.cos(a + 1))), u * 0.5, _cyan, 0.2);

    // Fine dot grid, brighter near the top.
    final dot = Paint();
    const gap = 22.0;
    for (var y = gap / 2; y < h * 0.55; y += gap) {
      final fade = 1 - y / (h * 0.55);
      dot.color = Colors.white.withValues(alpha: 0.06 * fade);
      for (var x = gap / 2; x < w; x += gap) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }

    // Sparkles rising slowly (deterministic positions, looped).
    final sparkle = Paint();
    for (var i = 0; i < 26; i++) {
      final seed = (i * 7919) % 1000 / 1000;
      final speed = 0.6 + (i % 5) * 0.15;
      final p = (t.value * speed + seed) % 1;
      final x = w * ((i * 37 % 100) / 100) + 8 * math.sin(a * 2 + i);
      final y = h * (1.05 - p * 1.1);
      final twinkle = 0.25 + 0.5 * (0.5 + 0.5 * math.sin(a * 3 + i));
      sparkle.color = (i % 4 == 0 ? AppColors.mint : Colors.white).withValues(alpha: twinkle * (1 - (p - 0.5).abs() * 1.4).clamp(0, 1));
      canvas.drawCircle(Offset(x, y), 1 + (i % 3) * 0.6, sparkle);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}

/// Ripples expanding from the logo plus two tilted orbit rings with coins.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.loop, this.pulse) : super(repaint: Listenable.merge([loop, pulse]));
  final Animation<double> loop;
  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;

    // Two staggered ripples.
    for (final offset in const [0.0, 0.5]) {
      final p = (pulse.value + offset) % 1;
      final r = 56 + (maxR - 56) * Curves.easeOut.transform(p);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.28 * (1 - p)),
      );
    }

    final a = loop.value * 2 * math.pi;
    void orbit({required double rx, required double ry, required double tilt, required double speed, required List<(double, Color, double)> coins}) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      final oval = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.16),
      );
      for (final (phase, color, radius) in coins) {
        final ang = a * speed + phase;
        final p = Offset(rx * math.cos(ang), ry * math.sin(ang));
        canvas.drawCircle(p, radius + 4, Paint()..color = color.withValues(alpha: 0.18));
        canvas.drawCircle(p, radius, Paint()..color = color);
      }
      canvas.restore();
    }

    orbit(rx: 118, ry: 44, tilt: -0.42, speed: 1, coins: [(0, AppColors.mint, 4.5), (math.pi, const Color(0xFFFFC46B), 3.5)]);
    orbit(rx: 100, ry: 34, tilt: 0.55, speed: -1.4, coins: [(1.2, Colors.white, 3), (4.0, const Color(0xFF7CB8FF), 3.5)]);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => false;
}
