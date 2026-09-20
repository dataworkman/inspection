import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'icon_avatar.dart';

/// A headline number with a label, for dashboards.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.brand,
  });

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      key: ValueKey('metric-$label'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconAvatar(icon: icon, tone: tone),
          const SizedBox(height: AppSpacing.md),
          Text(value,
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.1)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
