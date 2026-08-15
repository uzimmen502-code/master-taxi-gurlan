import 'package:flutter/material.dart';

/// Марказдаги ярим шаффоф пуск/пауза тугмаси.
class TvPlayPauseBadge extends StatelessWidget {
  const TvPlayPauseBadge({
    super.key,
    required this.playing,
    required this.visible,
    required this.onTap,
  });

  final bool playing;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Center(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: playing ? 42 : 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
