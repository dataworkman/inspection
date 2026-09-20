import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.xxl * 1.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: AppColors.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.textFaint),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title,
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
