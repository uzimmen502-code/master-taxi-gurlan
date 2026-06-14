import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bosh ekran fon — och yashil (binafsha o‘rniga).
class HomeGreenBackground extends StatelessWidget {
  const HomeGreenBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.scaffold,
            AppColors.scaffoldGradientEnd,
          ],
        ),
      ),
    );
  }
}
