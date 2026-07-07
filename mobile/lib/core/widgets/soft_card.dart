import 'package:flutter/material.dart';

/// Consistent premium card surface used across the app: white/tinted
/// surface, hairline border, 16px radius, optional tap ripple. Replaces
/// the ad-hoc `Card(elevation: 0, ...)` copies for one cohesive look.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
