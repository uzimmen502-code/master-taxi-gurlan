import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/user_model.dart';
import '../../../models/food_product.dart';
import '../../../repositories/user_repository.dart';
import '../../../utils/food_catalog.dart';
import '../../../widgets/order_checkout_wallet_banner.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../controllers/food_controller.dart';

/// Таом сават bottom-sheet — нон каби битта ойнада: сават + манзил/телефон +
/// битта "Буюртма бериш" tugmasi. Coordinata профилдан (AddressGate орқали)
/// кафолатланади, кейин Cloud Function буюртмага қўшади.
class FoodCartSheet extends StatefulWidget {
  const FoodCartSheet({super.key});

  @override
  State<FoodCartSheet> createState() => _FoodCartSheetState();
}

class _FoodCartSheetState extends State<FoodCartSheet> {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _sendOrder() async {
    final loc = AppLocalizations.of(context)!;
    final c = context.read<FoodController>();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
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

    // Манзил кафолати — курьер координатани профилдан олиши учун.
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

    final UserModel user = profile;
    final deliveryText = user.address.formatted;

    setState(() => _isSending = true);
    try {
      final result = await c.submitOrder(
        address: deliveryText,
        phone: phone,
      );

      if (!mounted) return;
      if (!result.success) {
        _showError(result.error ?? loc.translate('bread_error_fallback'));
        return;
      }

      final isOffline = result.isOffline;
      final rootMessenger = ScaffoldMessenger.of(
        Navigator.of(context, rootNavigator: true).context,
      );
      Navigator.of(context).pop();
      rootMessenger.showSnackBar(
        SnackBar(
          content: Text(isOffline
              ? loc.translate('bread_snack_order_saved_offline')
              : loc.translate('bread_snack_order_sent')),
          backgroundColor: isOffline ? Colors.orange : _primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showError(loc.translate('bread_error_fallback'));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatQty(double qty, String unit) {
    if (qty == qty.roundToDouble()) return '${qty.toInt()} $unit';
    return '$qty $unit';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<FoodController>();

    if (c.cart.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    final cartEntries = c.cart.entries.toList(growable: false);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(loc.translate('cart'),
                style: const TextStyle(
                    fontSize: AppText.titleLarge,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                c.clearCart();
                Navigator.of(context).pop();
              },
              child: const Icon(Icons.close, color: Colors.grey),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── Сават рўйхати ───
                ...cartEntries.map((entry) {
                  FoodProduct? p;
                  for (final e in c.products) {
                    if (e.id == entry.key) {
                      p = e;
                      break;
                    }
                  }
                  p ??= FoodCatalog.products
                      .where((e) => e.id == entry.key)
                      .cast<FoodProduct?>()
                      .firstWhere((e) => e != null, orElse: () => null);
                  if (p == null) return const SizedBox.shrink();
                  final product = p;
                  final qty = entry.value;
                  final itemTotal = (product.price * qty).round();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Text(product.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                style: const TextStyle(
                                    fontSize: AppText.bodyMedium,
                                    fontWeight: FontWeight.w600)),
                            Text('${formatPrice(itemTotal)} ${loc.translate("sum")}',
                                style: const TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => c.decrease(product.id),
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red, size: 24),
                      ),
                      Text(_formatQty(qty, product.unit),
                          style: const TextStyle(
                              fontSize: AppText.bodyMedium,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: () => c.increase(product.id),
                        icon: const Icon(Icons.add_circle_outline,
                            color: _green, size: 24),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 8),
                // ─── Жами ───
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _green.withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Text(loc.translate('total'),
                          style: const TextStyle(
                              fontSize: AppText.titleSmall,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${formatPrice(c.cartTotal)} ${loc.translate("sum")}',
                          style: const TextStyle(
                              fontSize: AppText.titleMedium,
                              fontWeight: FontWeight.bold,
                              color: _green)),
                    ]),
                    const SizedBox(height: 10),
                    OrderCheckoutWalletBanner(
                      orderTotal: c.cartTotal,
                      walletBalance: c.walletBalance,
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                // ─── Контакт ───
                Text(loc.translate('bread_cart_contact_section'),
                    style: const TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _inputField(_nameCtrl, loc.translate('bread_hint_name'),
                    TextInputType.name),
                const SizedBox(height: 8),
                _inputField(_addrCtrl, loc.translate('bread_hint_address'),
                    TextInputType.streetAddress),
                const SizedBox(height: 8),
                _inputField(_phoneCtrl, loc.translate('bread_hint_phone'),
                    TextInputType.phone),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendOrder,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18),
                    label: Text(
                        _isSending
                            ? loc.translate('bread_sending')
                            : loc.translate('bread_confirm_order'),
                        style: const TextStyle(
                            fontSize: AppText.titleSmall,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    loc.translate('bread_order_confirm_note'),
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Colors.grey.shade400),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _inputField(
      TextEditingController ctrl, String hint, TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _green, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
