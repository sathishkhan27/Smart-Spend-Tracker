import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../theme/app_colors.dart';

/// App-wide status strip: grey "offline" while disconnected, a short green
/// "back online" when the connection returns. It takes the status-bar area
/// and pushes the app down, so it never covers titles or buttons.
class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

enum _Strip { hidden, offline, backOnline }

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  _Strip _strip = _Strip.hidden;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _onChange(bool? was, bool online) {
    _hide?.cancel();
    if (!online) {
      setState(() => _strip = _Strip.offline);
    } else if (was == false) {
      setState(() => _strip = _Strip.backOnline);
      _hide = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _strip = _Strip.hidden);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(onlineProvider, (prev, next) {
      final online = next.value;
      if (online != null) _onChange(prev?.value, online);
    });

    final mq = MediaQuery.of(context);
    final visible = _strip != _Strip.hidden;
    final offline = _strip == _Strip.offline;
    return Column(children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: !visible
            ? const SizedBox(width: double.infinity)
            : AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: double.infinity,
                color: offline ? const Color(0xFF3A4556) : AppColors.income,
                padding: EdgeInsets.only(top: mq.padding.top + 3, bottom: 5, left: 16, right: 16),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                  child: Semantics(
                  liveRegion: true,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(offline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        offline ? "You're offline • showing saved data" : 'Back online • syncing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                      ),
                    ),
                  ]),
                ),
                ),
              ),
      ),
      Expanded(
        // The strip already covers the status bar, so pages drop their top inset.
        child: visible ? MediaQuery.removePadding(context: context, removeTop: true, child: widget.child) : widget.child,
      ),
    ]);
  }
}
