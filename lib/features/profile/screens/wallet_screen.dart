import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/wallet_topup_status.dart';
import '../widgets/wallet_section.dart';
import '../widgets/wallet_telegram_link_panel.dart';
import '../widgets/wallet_topup_notice.dart';
import '../widgets/wallet_topup_requests.dart';
import '../widgets/wallet_withdraw_panel.dart';

/// Ҳамён — баланс + Telegram тўлдириш (+ сўровлар ҳолати) + ечиш.
///
/// Экран очилганда тўлдириш ишлайдими текширилади (`getWalletTopUpStatus`):
/// бот ўчиқ ёки карта созланмаган бўлса фойдаланувчи ботга бормасдан сабабини
/// кўради. Текшириш йиқилса — блокланмайди (ҳолат номаълум).
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.phone, this.statusLoader, this.suggestedAmount});

  final String phone;

  /// Харид учун етишмаётган сумма — «қанча тўлдирасиз» қадамида таклиф бўлади.
  final int? suggestedAmount;

  /// Тест учун алмаштириладиган юкловчи.
  final Future<WalletTopUpStatus?> Function()? statusLoader;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletTopUpStatus? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final s = await (widget.statusLoader ?? loadWalletTopUpStatus)();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    // `null` (номаълум) — блокланмайди.
    final enabled = _status?.ready ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('wlt_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            WalletSection(phone: widget.phone, showTitle: false),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  WalletTopUpNotice(status: _status),
                  WalletTelegramLinkPanel(
                    phone: widget.phone,
                    enabled: enabled,
                    suggestedAmount: widget.suggestedAmount,
                    maxAmount: _status?.maxTopUp ?? 0,
                  ),
                  WalletTopUpRequests(uid: widget.phone),
                  WalletWithdrawPanel(phone: widget.phone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
