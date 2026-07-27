import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/user_repository.dart';
import '../../../widgets/order_checkout_wallet_banner.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../controllers/platform_store_controller.dart';

/// Соддалаштирилган сават: фақат товарлар + жами + буюртма.
/// Ётказиш/олиб кетиш, исм/телефон/манзил, ҳамён — бу ерда йўқ.
/// «Буюртма бериш» → тўлов тасдиғида ҳамён кўринади, сўнг профиль+манзил билан юборилади.
class PlatformCartSheet extends StatefulWidget {
  const PlatformCartSheet({super.key});

  @override
  State<PlatformCartSheet> createState() => _PlatformCartSheetState();
}

class _PlatformCartSheetState extends State<PlatformCartSheet> {
  static const _green = AppColors.primaryDark;
  static const _primary = AppColors.primary;

  bool _isSending = false;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      Navigator.of(context, rootNavigator: true).context,
    ).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _sendOrder() async {
    final loc = AppLocalizations.of(context)!;
    final c = context.read<PlatformStoreController>();

    if (FirebaseAuth.instance.currentUser == null) {
      _showError(loc.translate('auth_required_to_order'));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString('user_phone') ?? '').trim();
    if (phone.isEmpty || phoneDigits(phone).length < 9) {
      return _showError(loc.translate('bread_error_phone_invalid'));
    }

    // Тўлов пайти: ҳамён маълумоти шу диалогда.
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('platform_store_checkout')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${context.tr('platform_store_total')}: '
              '${formatPrice(c.cartTotal)} ${loc.translate('sum')}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            OrderCheckoutWalletBanner(
              orderTotal: c.cartTotal,
              walletBalance: c.walletBalance,
              walletApply: c.walletApplyAmount,
              cashDue: c.cashDuePreview,
            ),
            const SizedBox(height: 8),
            const Text(
              'Манзил ва телефон профилингиздан олинади. '
              'Буюртма етказиш учун юборилади.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('platform_store_checkout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    c.setFulfillmentMode('delivery');
    final uid = phoneDigits(phone);
    final userRepo = context.read<UserRepository>();
    var profile = uid.length >= 9 ? await userRepo.getById(uid) : null;
    if (profile == null || !profile.address.isComplete) {
      if (!mounted) return;
      final filled = await AddressGate.ensureFilled(context, user: profile);
      if (filled == null) return;
      profile = await userRepo.getById(uid);
      if (!mounted) return;
      if (profile == null || !profile.address.isComplete) {
        return _showError(loc.translate('bread_error_address_required'));
      }
    }
    final deliveryText = profile.address.formatted;

    setState(() => _isSending = true);
    try {
      final result = await c.submitOrder(address: deliveryText, phone: phone);
      if (!mounted) return;
      if (!result.success) {
        _showError(result.error ?? loc.translate('bread_error_fallback'));
        return;
      }
      final rootMessenger = ScaffoldMessenger.of(
        Navigator.of(context, rootNavigator: true).context,
      );
      Navigator.of(context).pop();
      rootMessenger.showSnackBar(
        SnackBar(
          content: Text(loc.translate('bread_snack_order_sent')),
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showError(loc.translate('bread_error_fallback'));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<PlatformStoreController>();
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (c.cart.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('platform_store_cart_title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    c.clearCart();
                    Navigator.pop(context);
                  },
                  child: Text(context.tr('platform_store_clear_cart')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in c.cart.entries)
                  _CartLine(id: e.key, qty: e.value),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        context.tr('platform_store_total'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${formatPrice(c.cartTotal)} ${loc.translate('sum')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _green,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_isSending || c.isSubmitting) ? null : _sendOrder,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.button,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: (_isSending || c.isSubmitting)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.tr('platform_store_checkout')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.id, required this.qty});

  final String id;
  final int qty;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final p = c.productOf(id);
    if (p == null) return const SizedBox.shrink();
    final line = p.price * qty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatPrice(line)} сўм',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => c.decrease(id),
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          ),
          Text(
            '$qty ${p.unit}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: () => c.increase(id),
            icon: const Icon(
              Icons.add_circle_outline,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
