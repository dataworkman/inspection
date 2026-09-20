import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one surface used for content blocks: white, hairline border, rounded.
/// Tappable when [onTap] is given.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Padding(
      padding: margin,
      child: Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
