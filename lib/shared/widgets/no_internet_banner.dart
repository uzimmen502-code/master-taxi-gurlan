import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';

/// "Интернет йўқ" banner — қайта ишлатилувчи.
class NoInternetBanner extends StatelessWidget {
  const NoInternetBanner({
    super.key,
    this.message,
    this.color = const Color(0xFFB71C1C),
  });

  /// `null` бўлса — `no_internet` калити (3 тилда).
  final String? message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.wifi_off, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(
          message ?? context.tr('no_internet'),
          style: const TextStyle(
              color: Colors.white,
              fontSize: AppText.bodyMedium,
              fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }
}
