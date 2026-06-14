import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/wallet_section.dart';

/// Кошелёк — баланс (тарихсиз).
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кошелёк'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: WalletSection(phone: phone, showTitle: false),
      ),
    );
  }
}
