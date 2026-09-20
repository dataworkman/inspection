import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small rounded label whose color carries the meaning (see [Tone]).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Tone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(tone);
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: colors.foreground, fontSize: dense ? 11 : 12);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: colors.foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
              child: Text(label,
                  style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
