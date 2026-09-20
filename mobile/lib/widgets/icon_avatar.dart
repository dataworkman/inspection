import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rounded square holding an icon in a tone's colors.
class IconAvatar extends StatelessWidget {
  const IconAvatar(
      {super.key, required this.icon, this.tone = Tone.brand, this.size = 40});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.5, color: colors.foreground),
    );
  }
}
