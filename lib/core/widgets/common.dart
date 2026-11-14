import 'package:flutter/material.dart';

import '../errors/failures.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

export 'app_logo.dart';

/// Rounded card with a soft shadow.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color, this.gradient, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  /// Highlight outline (e.g. due/overdue alerts).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radius);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.cardColor) : null,
        gradient: gradient,
        borderRadius: radius,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1.5)
            : (context.isDark || gradient != null ? null : Border.all(color: AppColors.divider.withValues(alpha: 0.7))),
        boxShadow: context.isDark
            ? null
            : gradient != null
                ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12))]
                : [BoxShadow(color: AppColors.navy.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(children: [
          // Soft decorative rings on gradient (hero) cards.
          if (gradient != null) ...[
            Positioned(right: -40, top: -50, child: _Ring(size: 170, alpha: 0.07)),
            Positioned(right: 40, bottom: -70, child: _Ring(size: 130, alpha: 0.05)),
          ],
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [Colors.white.withValues(alpha: alpha * 1.6), Colors.white.withValues(alpha: alpha * 0.4)]),
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.subtitle});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(subtitle!, style: context.text.bodySmall?.copyWith(color: context.secondaryText)),
                ],
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _EmptyIllustration(icon: icon),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                ),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: context.secondaryText, height: 1.5),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 20)),
                    icon: Icon(action == 'Retry' ? Icons.refresh_rounded : Icons.add_rounded, size: 18),
                    label: Text(action!),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Layered circles with a soft gradient and two accent dots.
class _EmptyIllustration extends StatelessWidget {
  const _EmptyIllustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        height: 88,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.blue.withValues(alpha: 0.16), AppColors.mint.withValues(alpha: 0.12)],
              ),
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.cardColor,
              boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Icon(icon, size: 28, color: AppColors.blue),
          ),
          const Positioned(top: 6, right: 8, child: _Dot(8, AppColors.mint)),
          const Positioned(bottom: 10, left: 6, child: _Dot(6, AppColors.warning)),
        ]),
      );
}

class _Dot extends StatelessWidget {
  const _Dot(this.size, this.color);
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load data',
        message: ErrorHandler.map(error).message,
        action: onRetry == null ? null : 'Retry',
        onAction: onRetry,
      );
}

/// Pulsing placeholder used while Firestore data loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: context.isDark ? Colors.white12 : AppColors.divider,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

/// A labelled progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, required this.color, this.height = 6});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.expense : AppColors.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}

/// Gradient scaffold background used by onboarding screens.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({super.key, required this.child, this.step, this.totalSteps = 5, this.onBack});
  final Widget child;
  final int? step;
  final int totalSteps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: onBack == null ? null : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
          automaticallyImplyLeading: false,
          title: step == null
              ? null
              : Row(
                  children: List.generate(
                    totalSteps,
                    (i) => Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= step! ? AppColors.blue : (context.isDark ? Colors.white12 : AppColors.divider),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        body: SafeArea(child: child),
      );
}
