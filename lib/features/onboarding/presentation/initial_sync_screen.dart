import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../sync/data/background_sync.dart';
import '../../sync/data/sync_service.dart';
import '../../sync/domain/sync_progress.dart';

/// Dashboard generation screen shown after first connecting data sources.
/// Every number on this screen comes from the live [SyncProgress] stream.
class InitialSyncScreen extends ConsumerStatefulWidget {
  const InitialSyncScreen({super.key});

  @override
  ConsumerState<InitialSyncScreen> createState() => _InitialSyncScreenState();
}

class _InitialSyncScreenState extends ConsumerState<InitialSyncScreen> with TickerProviderStateMixin {
  late final _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final _success = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _allowBackground = false;
  bool _finished = false;
  Timer? _bgTimer;

  @override
  void initState() {
    super.initState();
    _bgTimer = Timer(const Duration(seconds: 8), () => mounted ? setState(() => _allowBackground = true) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _orbit.dispose();
    _spin.dispose();
    _success.dispose();
    _bgTimer?.cancel();
    super.dispose();
  }

  Future<void> _start({bool sms = true, bool gmail = true}) async {
    final ctx = ref.read(processingContextProvider);
    if (ctx == null) return;
    final result = await ref.read(syncServiceProvider).run(SyncRequest(ctx: ctx, initial: true, includeSms: sms, includeGmail: gmail));
    if (!mounted) return;
    if (result.progress.isComplete && !result.progress.hasFailures) _complete();
  }

  Future<void> _complete() async {
    if (_finished) return;
    _finished = true;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid != null) await ref.read(workspaceRepositoryProvider).updateProfile(uid, {'initialSyncComplete': true});
    _success.forward();
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (mounted) context.go(Routes.home);
  }

  Future<void> _continueInBackground() async {
    await BackgroundSync.runSoon().catchError((_) {});
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(syncProgressProvider).value ?? ref.read(syncServiceProvider).current;
    final done = p.isComplete;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 48),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(done ? 'All set!' : 'Building your dashboard',
                        style: context.text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 250,
                      child: done
                          ? _SuccessBadge(animation: _success, total: p.identified)
                          : _ProgressRing(progress: p, orbit: _orbit, spin: _spin),
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child),
                      ),
                      child: Text(
                        done ? '${p.identified} transactions collected' : p.stage.message,
                        key: ValueKey(done ? 'done' : p.stage),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _StatsGrid(progress: p),
                    const SizedBox(height: 16),
                    ..._sourceRows(p),
                    const SizedBox(height: 24),
                    if (done)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                        onPressed: _complete,
                        child: const Text('Open dashboard'),
                      )
                    else if (p.stage == SyncStage.failed)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                        onPressed: () => _start(),
                        child: const Text('Retry'),
                      ),
                    if (!done && (_allowBackground || p.stage == SyncStage.failed))
                      TextButton(
                        onPressed: _continueInBackground,
                        child: const Text('Continue in background', style: TextStyle(color: Colors.white)),
                      ),
                    if (!done && !_allowBackground)
                      const Text('Already-synced records are saved even if you leave.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sourceRows(SyncProgress p) {
    const names = {'sms': ('SMS inbox', Icons.sms_rounded), 'gmail': ('Gmail', Icons.mail_rounded)};
    return [
      for (final e in p.sources.entries)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(names[e.key]?.$2 ?? Icons.source_rounded, color: Colors.white70, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(names[e.key]?.$1 ?? e.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (e.value.error != null || e.value.detail != null)
                  Text(e.value.error ?? e.value.detail!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            switch (e.value.status) {
              SourceSyncStatus.running => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SourceSyncStatus.done => const Icon(Icons.check_circle_rounded, color: AppColors.income),
              SourceSyncStatus.skipped => const Icon(Icons.remove_circle_outline_rounded, color: Colors.white38),
              SourceSyncStatus.failed => TextButton(
                  onPressed: p.isRunning ? null : () => _start(sms: e.key == 'sms', gmail: e.key == 'gmail'),
                  child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              SourceSyncStatus.idle => const SizedBox(),
            },
          ]),
        ),
    ];
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.orbit, required this.spin});
  final SyncProgress progress;
  final Animation<double> orbit;
  final Animation<double> spin;

  static const _icons = [
    (Icons.restaurant_rounded, Color(0xFFF97316)),
    (Icons.shopping_bag_rounded, Color(0xFFEC4899)),
    (Icons.bolt_rounded, Color(0xFFEAB308)),
    (Icons.flight_rounded, Color(0xFF0EA5E9)),
    (Icons.account_balance_rounded, AppColors.income),
    (Icons.local_gas_station_rounded, AppColors.expense),
  ];

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    return AnimatedBuilder(
      animation: Listenable.merge([orbit, spin]),
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < _icons.length; i++)
            Transform.translate(
              offset: Offset.fromDirection(orbit.value * 2 * math.pi + i * 2 * math.pi / _icons.length, 112),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ]),
                child: Icon(_icons[i].$1, size: 18, color: _icons[i].$2),
              ),
            ),
          SizedBox(
            width: 170,
            height: 170,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction ?? 0),
              duration: const Duration(milliseconds: 500),
              builder: (_, v, __) => CustomPaint(
                painter: _RingPainter(value: fraction == null ? null : v, spin: spin.value),
                child: Center(
                  child: fraction == null
                      ? const Icon(Icons.insights_rounded, color: Colors.white, size: 44)
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${(v * 100).round()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
                          const Text('processed', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.spin});
  final double? value;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawArc(rect.deflate(6), 0, 2 * math.pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [Color(0xFF7DD3FC), Colors.white, Color(0xFF86EFAC)]).createShader(rect);
    if (value == null) {
      // Indeterminate: rotating arc — no fake percentage.
      canvas.drawArc(rect.deflate(6), spin * 2 * math.pi, math.pi * 0.6, false, arc);
    } else {
      canvas.drawArc(rect.deflate(6), -math.pi / 2, 2 * math.pi * value!, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value || old.spin != spin;
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge({required this.animation, required this.total});
  final Animation<double> animation;
  final int total;

  @override
  Widget build(BuildContext context) => Center(
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.income.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 4)],
            ),
            child: const Icon(Icons.check_rounded, size: 96, color: AppColors.income),
          ),
        ),
      );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.progress});
  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final items = [
      (Icons.sms_outlined, 'SMS scanned', p.smsTotal == null || p.smsTotal == 0 ? '${p.smsScanned}' : '${p.smsScanned}/${p.smsTotal}'),
      (Icons.mail_outline_rounded, 'Emails scanned', p.emailsTotal == null || p.emailsTotal == 0 ? '${p.emailsScanned}' : '${p.emailsScanned}/${p.emailsTotal}'),
      (Icons.receipt_long_outlined, 'Transactions found', '${p.identified}'),
      (Icons.category_outlined, 'Categorized', '${p.categorized}'),
      (Icons.cloud_done_outlined, 'Synced', '${p.synced}'),
      (Icons.copy_all_rounded, 'Duplicates merged', '${p.duplicates}'),
    ];
    return GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        for (final (icon, label, value) in items)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white70, size: 20),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(value, key: ValueKey(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }
}
