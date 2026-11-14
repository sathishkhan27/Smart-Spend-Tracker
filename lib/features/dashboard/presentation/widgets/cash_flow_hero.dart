import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';

/// Home summary card: net cash flow, a ring that splits income vs spending
/// (savings % in the centre), and inflow/outflow tiles, over a slowly
/// drifting gradient backdrop. Motion stops when the OS asks to reduce it.
class CashFlowHero extends StatefulWidget {
  const CashFlowHero({
    super.key,
    required this.inflow,
    required this.outflow,
    required this.currency,
    required this.periodLabel,
    this.footer,
    this.onInflowTap,
    this.onOutflowTap,
  });

  final double inflow;
  final double outflow;
  final String currency;
  final String periodLabel;

  /// Optional chips (refunds, needs review…).
  final Widget? footer;

  /// Open the inflow / outflow transaction lists.
  final VoidCallback? onInflowTap;
  final VoidCallback? onOutflowTap;

  @override
  State<CashFlowHero> createState() => _CashFlowHeroState();
}

class _CashFlowHeroState extends State<CashFlowHero> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  static const _mintRing = Color(0xFF4ADEA0);
  static const _orangeRing = Color(0xFFFFA26B);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.inflow - widget.outflow;
    final saved = widget.inflow <= 0 ? null : net / widget.inflow * 100;
    final total = widget.inflow + widget.outflow;
    final inShare = total == 0 ? 0.0 : widget.inflow / total;
    final outShare = total == 0 ? 0.0 : widget.outflow / total;
    const radius = 26.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: const Color(0xFF3B2FB8).withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: _DriftPainter(_drift))),
          ),
          // Hairline inner border for a glassy edge.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Chip(widget.periodLabel),
                    const SizedBox(height: 12),
                    const Text('Net cash flow', style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: net),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${v < 0 ? '−' : ''}${Fmt.money(v.abs(), currency: widget.currency)}',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          size: 16, color: net >= 0 ? _mintRing : _orangeRing),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          net >= 0 ? 'Income ahead of spending' : 'Spending above income',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                _CashRing(inShare: inShare, outShare: outShare, saved: saved, inColor: _mintRing, outColor: _orangeRing),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _FlowTile(
                    icon: Icons.south_west_rounded,
                    color: _mintRing,
                    label: 'Inflow',
                    value: Fmt.money(widget.inflow, currency: widget.currency),
                    share: inShare,
                    onTap: widget.onInflowTap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FlowTile(
                    icon: Icons.north_east_rounded,
                    color: _orangeRing,
                    label: 'Outflow',
                    value: Fmt.money(widget.outflow, currency: widget.currency),
                    share: outShare,
                    onTap: widget.onOutflowTap,
                  ),
                ),
              ]),
              if (widget.footer != null) ...[const SizedBox(height: 12), widget.footer!],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Split ring: mint = income share, orange = spending share; centre = saved %.
class _CashRing extends StatelessWidget {
  const _CashRing({required this.inShare, required this.outShare, required this.saved, required this.inColor, required this.outColor});
  final double inShare;
  final double outShare;
  final double? saved;
  final Color inColor;
  final Color outColor;

  @override
  Widget build(BuildContext context) {
    const size = 108.0;
    final savedText = saved == null ? '—' : '${saved!.clamp(-999, 100).round()}%';
    return Semantics(
      label: saved == null ? 'No income recorded' : 'Saved $savedText of income',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(progress: t, inShare: inShare, outShare: outShare, inColor: inColor, outColor: outColor),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(savedText, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1)),
                Text(saved != null && saved! < 0 ? 'overspent' : 'saved',
                    style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.inShare, required this.outShare, required this.inColor, required this.outColor});
  final double progress;
  final double inShare;
  final double outShare;
  final Color inColor;
  final Color outColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    // Track + inner glass disc.
    canvas.drawCircle(center, r - stroke / 2 - 4, Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    if (inShare + outShare == 0) return;
    const gap = 0.07; // radians between segments
    const start = -math.pi / 2;
    final full = 2 * math.pi * progress;
    final inSweep = math.max(0.0, full * inShare - (outShare > 0 ? gap : 0));
    final outSweep = math.max(0.0, full * outShare - (inShare > 0 ? gap : 0));

    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;

    if (inSweep > 0) canvas.drawArc(rect, start + gap / 2, inSweep, false, arc(inColor));
    if (outSweep > 0) canvas.drawArc(rect, start + full * inShare + gap / 2, outSweep, false, arc(outColor));
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.inShare != inShare || old.outShare != outShare;
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.icon, required this.color, required this.label, required this.value, required this.share, this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double share;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(children: [
          // Circular icon badge with a mini progress ring.
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share.clamp(0, 1)),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 3,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: const Color(0xFF1B1F4B)),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white70),
        ]),
      ),
      ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Animated backdrop: blue→violet gradient with drifting glow bubbles and
/// slowly turning outline circles. Repaints only this layer.
class _DriftPainter extends CustomPainter {
  _DriftPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final a = t.value * 2 * math.pi;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F6BF0), Color(0xFF4A4FE0), Color(0xFF6D3FD8)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );

    void bubble(Offset c, double r, Color color, double alpha) => canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: r)),
        );

    // Drifting glows on gentle Lissajous paths.
    bubble(Offset(w * (0.85 + 0.08 * math.cos(a)), h * (0.15 + 0.10 * math.sin(a))), w * 0.55, const Color(0xFF4ADEA0), 0.30);
    bubble(Offset(w * (0.15 + 0.10 * math.sin(a + 1.2)), h * (0.95 + 0.08 * math.cos(a * 2))), w * 0.6, const Color(0xFF00C2FF), 0.28);
    bubble(Offset(w * (0.55 + 0.12 * math.cos(a + 2.4)), h * (0.55 + 0.12 * math.sin(a + 0.6))), w * 0.35, const Color(0xFFFF8FB8), 0.16);

    // Outline circles that slowly orbit.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.10);
    final c1 = Offset(w * 0.78 + 10 * math.cos(a), -h * 0.05 + 8 * math.sin(a));
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(c1, h * 0.28 * i, ring);
    }
    final c2 = Offset(-w * 0.05 + 12 * math.sin(a), h * 1.05 + 10 * math.cos(a));
    canvas.drawCircle(c2, h * 0.38, ring);

    // Small floating dots.
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (var i = 0; i < 6; i++) {
      final p = a + i * 1.05;
      canvas.drawCircle(Offset(w * (0.1 + 0.15 * i) + 6 * math.cos(p), h * (0.25 + 0.5 * ((i * 37) % 10) / 10) + 6 * math.sin(p * 1.3)), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_DriftPainter old) => false;
}
