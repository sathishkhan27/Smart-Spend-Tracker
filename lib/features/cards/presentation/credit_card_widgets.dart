import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/formatters.dart';
import '../../upcoming/domain/due_status.dart';
import '../domain/card_cycle.dart';
import '../domain/credit_card.dart';

/// Brand-ish gradients per issuer (generic, not logos).
List<Color> cardGradient(String issuer) {
  final i = issuer.toLowerCase();
  if (i.contains('icici')) return const [Color(0xFF7A1F2B), Color(0xFFB4442A), Color(0xFFE07A2F)];
  if (i.contains('hdfc')) return const [Color(0xFF0B2A5B), Color(0xFF16418C), Color(0xFFC0272D)];
  if (i.contains('sbi')) return const [Color(0xFF0B3C7A), Color(0xFF1C6CC4), Color(0xFF35A7E0)];
  if (i.contains('axis')) return const [Color(0xFF5B0F2E), Color(0xFF8E1B47), Color(0xFFC2416F)];
  if (i.contains('kotak')) return const [Color(0xFF8B0F1A), Color(0xFFD12E2E), Color(0xFF1F3B73)];
  if (i.contains('amex') || i.contains('american')) return const [Color(0xFF0B5563), Color(0xFF138A9E), Color(0xFF63C5D5)];
  if (i.contains('idfc')) return const [Color(0xFF6B0F1A), Color(0xFF9C1C2B), Color(0xFF3B3F46)];
  return const [Color(0xFF142B4A), Color(0xFF2A4F8F), Color(0xFF3478F6)];
}

/// Physical-card style tile: issuer, chip, masked number, available limit
/// and pending due. [compact] is the Home carousel size.
class CreditCardVisual extends StatelessWidget {
  static const _designWidth = 330.0;

  const CreditCardVisual({super.key, required this.card, this.cycle, this.compact = true, this.onTap});
  final CreditCard card;

  /// Billing-cycle status (from cardCyclesProvider); null while loading.
  final CardCycle? cycle;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = cardGradient(card.issuer);
    final now = AppClock.now();
    final c = cycle;
    final unpaid = c != null && c.state.owing;
    final dueDate = c == null ? card.dueDate : (unpaid ? c.statementDueDate : c.nextDueDate);
    final due = unpaid && dueDate != null
        ? DueStatus.of(dueDate, now)
        : (c == null && card.pendingDue > 0 && card.dueDate != null ? DueStatus.of(card.dueDate!, now) : null);
    final r = BorderRadius.circular(22);
    return AspectRatio(
      aspectRatio: 1.586, // ISO card proportions
      child: Container(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _CardBackdrop(colors))),
                  // Laid out at one design size and scaled to fit, so the card
                  // never overflows on narrow screens or with larger text.
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: _designWidth,
                        height: _designWidth / 1.586,
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        card.issuer,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: compact ? 14 : 16, letterSpacing: 0.2),
                                      ),
                                    ),
                                    if (c != null && c.state == StatementState.paid)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
                                        child: const Text(
                                          'PAID ✓',
                                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                                        ),
                                      )
                                    else
                                      Transform.rotate(
                                        angle: math.pi / 2,
                                        child: const Icon(Icons.wifi_rounded, color: Colors.white70, size: 20),
                                      ),
                                  ],
                                ),
                                SizedBox(height: compact ? 4 : 14),
                                _Chip(small: compact),
                                const Spacer(),
                                Text(
                                  '••••  ••••  ••••  ${card.last4}',
                                  style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 18, fontWeight: FontWeight.w700, letterSpacing: 1.6),
                                ),
                                SizedBox(height: compact ? 4 : 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: card.availableLimit != null || c == null
                                          ? _Figure(label: 'AVAILABLE', value: card.availableLimit == null ? '—' : Fmt.compact(card.availableLimit!))
                                          : _Figure(label: 'THIS CYCLE', value: Fmt.compact(c.cycleSpent)),
                                    ),
                                    if (c != null && unpaid)
                                      _Figure(
                                        label: dueDate == null ? 'DUE' : 'DUE ${Fmt.shortDate(dueDate).toUpperCase()}',
                                        value: Fmt.compact(c.remaining),
                                        alignEnd: true,
                                        highlight: due?.level.color ?? AppColors.warning,
                                      )
                                    else if (c != null)
                                      // Paid / nothing owed: next due date with the amount building up this cycle.
                                      _Figure(
                                        label: dueDate == null ? 'THIS CYCLE' : 'NEXT DUE ${Fmt.shortDate(dueDate).toUpperCase()}',
                                        value: Fmt.compact(c.cycleSpent),
                                        alignEnd: true,
                                      )
                                    else if (card.pendingDue > 0)
                                      _Figure(
                                        label: due == null ? 'DUE' : 'DUE ${Fmt.shortDate(card.dueDate!).toUpperCase()}',
                                        value: Fmt.compact(card.pendingDue),
                                        alignEnd: true,
                                        highlight: due?.level.isAlert == true ? due!.level.color : null,
                                      ),
                                  ],
                                ),
                                if (card.utilization != null) ...[
                                  SizedBox(height: compact ? 5 : 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: card.utilization,
                                      minHeight: 4,
                                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                                      valueColor: AlwaysStoppedAnimation(card.utilization! > 0.75 ? const Color(0xFFFFB38A) : AppColors.mint),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.alignEnd = false, this.highlight});
  final String label;
  final String value;
  final bool alignEnd;
  final Color? highlight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8),
      ),
      const SizedBox(height: 1),
      Container(
        padding: highlight == null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: highlight == null ? null : BoxDecoration(color: highlight, borderRadius: BorderRadius.circular(6)),
        child: Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    width: small ? 30 : 34,
    height: small ? 21 : 25,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      gradient: const LinearGradient(colors: [Color(0xFFF6D88A), Color(0xFFC9A44C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: CustomPaint(painter: _ChipLines()),
  );
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), p);
    canvas.drawLine(Offset(s.width / 3, 0), Offset(s.width / 3, s.height), p);
    canvas.drawLine(Offset(2 * s.width / 3, 0), Offset(2 * s.width / 3, s.height), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CardBackdrop extends CustomPainter {
  _CardBackdrop(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.05), size.height * 0.6, ring);
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.05), size.height * 0.9, ring);
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 1.1),
      size.height * 0.7,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset(size.width * 0.15, size.height * 1.1), radius: size.height * 0.7)),
    );
  }

  @override
  bool shouldRepaint(_CardBackdrop old) => old.colors != colors;
}
