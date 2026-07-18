import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/wallet_p2p_panel.dart';
import '../widgets/wallet_section.dart';

/// Кошелёк — баланс + P2P сўровлар.
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
        child: Column(
          children: [
            WalletSection(phone: phone, showTitle: false),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WalletP2pPanel(phone: phone),
            ),
          ],
        ),
      ),
    );
  }
}
