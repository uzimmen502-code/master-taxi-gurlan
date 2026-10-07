import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Асосий экран фони — статик (эга қарори: анимацион фон чарчатган,
/// олиб ташланди). `AvaLight.bg` — 2026-10-07 дан Primary light `#FFF0D1`
/// (эга қарори; аввал нейтрал `#F3F5F8`).
class HomeAliveBackground extends StatelessWidget {
  const HomeAliveBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: AppColors.background);
  }
}
