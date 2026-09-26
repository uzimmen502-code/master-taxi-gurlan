import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Асосий экран фони — статик (эга қарори: анимацион фон чарчатган,
/// олиб ташланди). `AvaLight.bg` (#F3F5F8) — Avito услуби: нейтрал фон,
/// бренд ранги фақат қидирув майдони ва «Барча хизматлар» катагида.
class HomeAliveBackground extends StatelessWidget {
  const HomeAliveBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: AppColors.background);
  }
}
