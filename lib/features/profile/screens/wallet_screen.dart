import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../widgets/wallet_p2p_panel.dart';
import '../widgets/wallet_section.dart';
import '../widgets/wallet_telegram_link_panel.dart';

/// Кошелёк — баланс + Telegram тўлдириш + P2P.
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
              child: Column(
                children: [
                  WalletTelegramLinkPanel(phone: phone),
                  WalletP2pPanel(phone: phone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
