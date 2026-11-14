import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/notification_service.dart';

/// Shows notifications as a card that slides down from the top while the app
/// is open. Tap → opens the related page; swipe up → dismiss; auto-hides.
/// Several alerts in a row are shown one after another.
class ForegroundAlertHost extends ConsumerStatefulWidget {
  const ForegroundAlertHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ForegroundAlertHost> createState() => _ForegroundAlertHostState();
}

class _ForegroundAlertHostState extends ConsumerState<ForegroundAlertHost> {
  static const _visibleFor = Duration(seconds: 4);

  StreamSubscription<InAppAlert>? _sub;
  final _queue = Queue<InAppAlert>();
  InAppAlert? _current;
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(notificationServiceProvider).foregroundAlerts.listen((a) {
      _queue.add(a);
      if (_current == null) _next();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    _timer?.cancel();
    if (_queue.isEmpty) {
      setState(() => _current = null);
      return;
    }
    setState(() {
      _current = _queue.removeFirst();
      _shown = false;
    });
    // Slide in on the next frame, then auto-hide.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
    _timer = Timer(_visibleFor, _hide);
  }

  void _hide() {
    _timer?.cancel();
    if (!mounted || _current == null) return;
    setState(() => _shown = false);
    Timer(const Duration(milliseconds: 280), () {
      if (mounted) _next();
    });
  }

  void _open(InAppAlert a) {
    _hide();
    final route = a.route;
    if (route != null && route.isNotEmpty) openAppRoute(ref.read(routerProvider), route);
  }

  @override
  Widget build(BuildContext context) {
    final a = _current;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      widget.child,
      if (a != null)
        Positioned(
          left: 12,
          right: 12,
          top: top + 8,
          child: AnimatedSlide(
            offset: _shown ? Offset.zero : const Offset(0, -1.6),
            duration: const Duration(milliseconds: 280),
            curve: _shown ? Curves.easeOutBack : Curves.easeIn,
            child: AnimatedOpacity(
              opacity: _shown ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -100) _hide();
                },
                child: _AlertCard(alert: a, onTap: () => _open(a), onClose: _hide),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onTap, required this.onClose});
  final InAppAlert alert;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final k = alert.kind;
    return Material(
      color: context.cardColor,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: k.color.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: k.color, shape: BoxShape.circle),
              child: Icon(k.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(k.label.toUpperCase(),
                    style: context.text.labelSmall?.copyWith(color: k.color, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                Text(alert.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (alert.body.isNotEmpty)
                  Text(alert.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
              ]),
            ),
            // No IconButton/tooltip here: this banner lives above the Navigator,
            // where there is no Overlay (tooltips need one and would throw).
            Semantics(
              button: true,
              label: 'Dismiss',
              child: InkResponse(
                onTap: onClose,
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, size: 18, color: context.secondaryText),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
