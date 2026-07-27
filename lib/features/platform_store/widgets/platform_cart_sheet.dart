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

/// Платформа савати: миқдор + етказиш/олиб кетиш + ҳамён + буюртма.
class PlatformCartSheet extends StatefulWidget {
  const PlatformCartSheet({super.key});

  @override
  State<PlatformCartSheet> createState() => _PlatformCartSheetState();
}

class _PlatformCartSheetState extends State<PlatformCartSheet> {
  static const _green = AppColors.primaryDark;
  static const _primary = AppColors.primary;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('user_name') ?? '';
    final savedPhone = prefs.getString('user_phone') ?? '';
    var savedAddress = prefs.getString('user_address') ?? '';

    if (savedAddress.isEmpty) {
      try {
        final uid = phoneDigits(savedPhone);
        if (uid.length >= 9 && mounted) {
          final user = await context.read<UserRepository>().getById(uid);
          if (user != null) {
            if (user.address.isComplete) {
              savedAddress = user.address.formatted;
            } else if (user.addressLegacy.isNotEmpty) {
              savedAddress = user.addressLegacy;
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _nameCtrl.text = savedName;
      _phoneCtrl.text = savedPhone;
      _addrCtrl.text = savedAddress;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

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

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      return _showError(loc.translate('bread_error_name_required'));
    }
    if (phone.isEmpty || phone.length < 9) {
      return _showError(loc.translate('bread_error_phone_invalid'));
    }

    final isPickup = c.fulfillmentMode == 'pickup';
    var deliveryText = 'Olib ketish';
    if (!isPickup) {
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
        setState(() => _addrCtrl.text = profile!.address.formatted);
      }
      deliveryText = profile.address.formatted;
    }

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
      height: MediaQuery.of(context).size.height * 0.92,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ModeChip(
                          label: 'Етказиш',
                          selected: c.fulfillmentMode == 'delivery',
                          onTap: () => c.setFulfillmentMode('delivery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ModeChip(
                          label: 'Олиб кетиш',
                          selected: c.fulfillmentMode == 'pickup',
                          onTap: () => c.setFulfillmentMode('pickup'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              context.tr('platform_store_total'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                        const SizedBox(height: 10),
                        OrderCheckoutWalletBanner(
                          orderTotal: c.cartTotal,
                          walletBalance: c.walletBalance,
                          walletApply: c.walletApplyAmount,
                          cashDue: c.cashDuePreview,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: loc.translate('name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneCtrl,
                    decoration: InputDecoration(
                      labelText: loc.translate('phone'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  if (c.fulfillmentMode != 'pickup') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addrCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: loc.translate('address'),
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.place_outlined),
                      ),
                    ),
                  ],
                ],
              ),
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
          Text('$qty ${p.unit}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: () => c.increase(id),
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.button : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
