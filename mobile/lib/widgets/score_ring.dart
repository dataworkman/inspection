import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A circular gauge for a score out of 100. Shows a dash when there is none.
class ScoreRing extends StatelessWidget {
  const ScoreRing(
      {super.key, required this.score, this.size = 64, this.caption});

  final num? score;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(toneForScore(score));
    final theme = Theme.of(context);
    final value = ((score ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: size / 9,
              color: colors.background,
            ),
          ),
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: size / 9,
              strokeCap: StrokeCap.round,
              color: colors.foreground,
              backgroundColor: Colors.transparent,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score == null ? '-' : _format(score!),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: size * 0.3,
                    color: colors.foreground,
                    height: 1.1),
              ),
              if (caption != null)
                Text(caption!,
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: size * 0.14, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(num score) => score == score.roundToDouble()
      ? score.toInt().toString()
      : score.toStringAsFixed(1);
}
