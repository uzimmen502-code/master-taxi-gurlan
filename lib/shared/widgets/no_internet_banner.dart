import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// "Интернет йўқ" banner — қайта ишлатилувчи.
class NoInternetBanner extends StatelessWidget {
  const NoInternetBanner({
    super.key,
    this.message = 'Интернет уланиши йўқ',
    this.color = const Color(0xFFB71C1C),
  });

  final String message;
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
          message,
          style: const TextStyle(
              color: Colors.white,
              fontSize: AppText.bodyMedium,
              fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }
}
