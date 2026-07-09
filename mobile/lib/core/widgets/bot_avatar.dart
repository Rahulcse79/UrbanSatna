import 'package:flutter/material.dart';

/// The support-bot mascot. Renders `assets/images/chat_bot.png` when the
/// asset exists and falls back to a themed robot glyph until it's added.
class BotAvatar extends StatelessWidget {
  const BotAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/chat_bot.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.smart_toy_rounded,
          size: size * 0.62,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
