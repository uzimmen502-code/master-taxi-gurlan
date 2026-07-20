import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/bread_extra_product.dart';
import '../../../models/bread_product.dart';
import '../../../repositories/user_repository.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/order_checkout_wallet_banner.dart';
import '../controllers/bread_controller.dart';
import 'extras_count_item.dart';

String _extraLineSubtitle(BreadExtraProduct p) {
  final price = formatPrice(p.price);
  final cap = p.caption.trim();
  if (cap.isNotEmpty) return '$cap — $price сўм';
  final q = p.qty;
  if (q != null && '$q'.trim().isNotEmpty) {
    return '${p.qty} ${p.unitRu} — $price сўм';
  }
  return '${p.unitRu} — $price сўм';
}

/// Сават bottom sheet — буюртмани якунлаш ва юбориш.
class BreadCartSheet extends StatefulWidget {
  const BreadCartSheet({super.key});

  @override
  State<BreadCartSheet> createState() => _BreadCartSheetState();
}

class _BreadCartSheetState extends State<BreadCartSheet> {
  static const _green = AppColors.primaryDark;
  static const _primary = AppColors.primary;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  bool _isSending = false;

  double? _deliveryLat;
  double? _deliveryLng;
  String? _deliveryAddress;

  @override
  void initState() {
    super.initState();
    final c = context.read<BreadController>();
    for (final entry in c.cart.entries) {
      final p = c.allProducts.firstWhere((p) => p.id == entry.key,
          orElse: () => _empty);
      if (p.id != 0 && (p.isYopish || p.isToy)) {
        c.flourMilkChoice.putIfAbsent(entry.key, () => 'ours');
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  static final BreadProduct _empty = const BreadProduct(
    id: 0,
    name: '',
    type: '',
  );

  Future<void> _loadProfile() async {
    final c = context.read<BreadController>();
    final profile = await c.loadUserProfile();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = profile.name;
      _phoneCtrl.text = profile.phone;
      _addrCtrl.text = profile.address;
    });

    final uid = phoneDigits(profile.phone);
    if (uid.length < 9) return;
    final user = await context.read<UserRepository>().getById(uid);
    if (!mounted || user == null || !user.address.isComplete) return;
    _resolveDeliveryLocation(user);
    if (!mounted) return;
    if (_deliveryAddress != null) {
      setState(() => _addrCtrl.text = _deliveryAddress!);
    }
  }

  void _resolveDeliveryLocation(UserModel profile) {
    final homeLat = profile.address.lat;
    final homeLng = profile.address.lng;
    if (homeLat == null || homeLng == null) {
      _deliveryLat = null;
      _deliveryLng = null;
      _deliveryAddress = null;
      return;
    }
    _deliveryLat = homeLat;
    _deliveryLng = homeLng;
    _deliveryAddress = profile.address.formatted;
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _sendOrder() async {
    final loc = AppLocalizations.of(context)!;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError(loc.translate('auth_required_to_order'));
      return;
    }

    final c = context.read<BreadController>();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty) {
      return _showError(loc.translate('bread_error_name_required'));
    }
    if (phone.isEmpty || phone.length < 9) {
      return _showError(loc.translate('bread_error_phone_invalid'));
    }

    final isPickup = c.fulfillmentMode == 'pickup';
    String deliveryText = 'Olib ketish';
    double? lat;
    double? lng;

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
        final filledProfile = profile;
        if (filledProfile == null || !filledProfile.address.isComplete) {
          return _showError(loc.translate('bread_error_address_required'));
        }
        profile = filledProfile;
        setState(() => _addrCtrl.text = filledProfile.address.formatted);
        _resolveDeliveryLocation(filledProfile);
        if (!mounted) return;
        if (_deliveryAddress != null) {
          setState(() => _addrCtrl.text = _deliveryAddress!);
        }
      }

      final user = profile;
      if (!user.address.isComplete) {
        return _showError(loc.translate('bread_error_address_required'));
      }

      _resolveDeliveryLocation(user);
      deliveryText = user.address.formatted;
      lat = _deliveryLat;
      lng = _deliveryLng;
    }

    setState(() => _isSending = true);
    try {
      final result = await c.sendOrder(
        name: name,
        phone: phone,
        address: deliveryText,
        deliveryLat: lat,
        deliveryLng: lng,
      );

      if (!mounted) return;
      if (!result.success) {
        _showError(result.error ?? loc.translate('bread_error_fallback'));
        return;
      }

      final isOffline = result.isOffline;
      c.clearCart();
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<BreadController>();
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
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(loc.translate('bread_cart_title'),
                style: const TextStyle(
                    fontSize: AppText.titleLarge,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
                onTap: () {
                  context.read<BreadController>().clearCart();
                  Navigator.of(context).pop();
                },
                child: const Icon(Icons.close, color: Colors.grey)),
          ]),
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
                      child: _BreadModeChip(
                        label: 'Yetkazish',
                        selected: c.fulfillmentMode == 'delivery',
                        onTap: () => c.setFulfillmentMode('delivery'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BreadModeChip(
                        label: 'Olib ketish',
                        selected: c.fulfillmentMode == 'pickup',
                        onTap: () => c.setFulfillmentMode('pickup'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(loc.translate('bread_cart_order_section'),
                    style: const TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...c.cart.entries.map((entry) {
                  final p = c.allProducts
                      .firstWhere((p) => p.id == entry.key, orElse: () => _empty);
                  if (p.id == 0) return const SizedBox.shrink();
                  return _CartItemTile(
                    product: p,
                    count: entry.value,
                    needsFlourMilk: p.isYopish || p.isToy,
                  );
                }),
                if (c.extraProducts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Text(
                        loc.translate('bread_section_extras'),
                        style: const TextStyle(
                            fontSize: AppText.bodyLarge,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        loc.translate('bread_optional_badge'),
                        style: const TextStyle(
                            fontSize: AppText.labelTiny,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  for (final p in c.extraProducts) ...[
                    if (!(p.tieToYopishBread && c.yopishTotalCount <= 0)) ...[
                      if (p.bonusEnabled && p.bonusThreshold > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            loc
                                .translate('bread_bonus_hint')
                                .replaceAll(
                                    '{threshold}', '${p.bonusThreshold}')
                                .replaceAll('{qty}', '${p.bonusQty}')
                                .replaceAll(
                                    '{percent}', '${p.bonusPercent}'),
                            style: TextStyle(
                                fontSize: AppText.labelTiny,
                                color: Colors.orange.shade700),
                          ),
                        ),
                      ExtrasCountItem(
                        emoji: p.displayEmoji,
                        name: p.name,
                        qty: _extraLineSubtitle(p),
                        count: c.extraProductsCart[p.id] ?? 0,
                        max: p.effectiveMaxQtyValue(c.yopishTotalCount),
                        qtyStep: p.qtyStep,
                        formatStepperCount: p.qtyCaptionNum,
                        onDecrement: () => c.bumpExtraQty(p.id, -1),
                        onIncrement: () => c.bumpExtraQty(p.id, 1),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ],
                const SizedBox(height: 16),
                const _PriceSummary(),
                const SizedBox(height: 16),
                Text(loc.translate('bread_cart_contact_section'),
                    style: const TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _inputField(
                    _nameCtrl, loc.translate('bread_hint_name'), TextInputType.name),
                const SizedBox(height: 8),
                if (c.fulfillmentMode != 'pickup') ...[
                  _inputField(_addrCtrl, loc.translate('bread_hint_address'),
                      TextInputType.streetAddress),
                  const SizedBox(height: 8),
                ],
                _inputField(
                    _phoneCtrl, loc.translate('bread_hint_phone'), TextInputType.phone),
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

// ─── Сават ичидаги маҳсулот тили + ун/сут танлови ───────────────────
class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.product,
    required this.count,
    required this.needsFlourMilk,
  });

  final BreadProduct product;
  final int count;
  final bool needsFlourMilk;

  static const _green = AppColors.primaryDark;
  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<BreadController>();
    final choice = c.flourMilkChoice[product.id] ?? 'ours';
    final color = product.isYopish ? _orange : _green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(product.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(product.name,
                style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600)),
          ),
          Text('× $count',
              style: TextStyle(
                  fontSize: AppText.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ]),
        if (needsFlourMilk) ...[
          const SizedBox(height: 8),
          Text(loc.translate('bread_flour_milk_label'),
              style: const TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: _choiceBtn(loc.translate('bread_flour_milk_ours'),
                    choice == 'ours',
                    () => c.setFlourMilkChoice(product.id, 'ours'))),
            const SizedBox(width: 8),
            Expanded(
                child: _choiceBtn(loc.translate('bread_flour_milk_yours'),
                    choice == 'yours',
                    () => c.setFlourMilkChoice(product.id, 'yours'))),
          ]),
          if (choice == 'ours') ...[
            const SizedBox(height: 4),
            _FlourMilkInfo(product: product, count: count),
          ],
        ],
      ]),
    );
  }

  Widget _choiceBtn(String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _green : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: AppText.bodySmall,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }
}

class _FlourMilkInfo extends StatelessWidget {
  const _FlourMilkInfo({required this.product, required this.count});

  final BreadProduct product;
  final int count;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<BreadController>();
    final flourG = product.flourG ?? 300;
    final milkMl = product.milkMl ??
        ((product.milkRatio ?? 0.575) * flourG).round();
    final cost = c.flourMilkCost(product, count);
    final totalG = flourG * count;
    final totalMl = milkMl * count;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
          child: Text(
            loc
                .translate('bread_flour_milk_amounts')
                .replaceAll('{g}', totalG.toString())
                .replaceAll('{ml}', totalMl.toString()),
            style: const TextStyle(
                fontSize: AppText.labelSmall, color: Colors.grey),
          ),
        ),
        Text(
            loc
                .translate('bread_flour_milk_cost')
                .replaceAll('{cost}', formatPrice(cost)),
            style: const TextStyle(
                fontSize: AppText.labelSmall,
                fontWeight: FontWeight.bold,
                color: _green)),
      ]),
    );
  }
}

// ─── Нархлар хулосаси + кошелёк ──────────────────────────────────────
class _PriceSummary extends StatelessWidget {
  const _PriceSummary();

  static const _green = AppColors.primaryDark;

  Widget _summaryRow(String label, String val, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: AppText.bodySmall,
                      color: color ?? Colors.grey.shade700))),
          Text('$val сўм',
              style: TextStyle(
                  fontSize: AppText.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<BreadController>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        ...c.cart.entries.map((entry) {
          final p = c.allProducts
              .firstWhere((p) => p.id == entry.key, orElse: () => _empty);
          if (p.id == 0) return const SizedBox.shrink();
          return _summaryRow(
              '${p.emoji} ${p.name} × ${entry.value}',
              formatPrice(c.productPrice(p) * entry.value));
        }),
        ...c.cart.entries.map((entry) {
          final p = c.allProducts
              .firstWhere((p) => p.id == entry.key, orElse: () => _empty);
          if (p.id == 0) return const SizedBox.shrink();
          final choice = c.flourMilkChoice[entry.key] ?? 'ours';
          if ((p.isYopish || p.isToy) && choice == 'ours') {
            return _summaryRow(
                loc
                    .translate('bread_summary_flour_milk')
                    .replaceAll('{name}', p.name),
                formatPrice(c.flourMilkCost(p, entry.value)),
                color: _green);
          }
          return const SizedBox.shrink();
        }),
        for (final p in c.extraProducts) ...[
          if ((c.extraProductsCart[p.id] ?? 0) > 1e-9) ...[
            _summaryRow(
              '${p.displayEmoji} ${p.name} (${p.qtyCaptionNum(c.extraProductsCart[p.id] ?? 0)})',
              formatPrice(p.lineTotal(c.extraProductsCart[p.id] ?? 0)),
              color: _green,
            ),
            if (p.discountFor(c.extraProductsCart[p.id] ?? 0) > 0)
              _summaryRow(
                loc.translate('bread_summary_bonus'),
                '-${formatPrice(p.discountFor(c.extraProductsCart[p.id] ?? 0))}',
                color: Colors.orange.shade700,
              ),
          ],
        ],
        if (c.saltYeastCost > 0) ...[
          const Divider(height: 12),
          _summaryRow(
            c.cartHasYopishBread
                ? loc.translate('bread_summary_salt_yeast_full')
                : loc.translate('bread_summary_salt_yeast'),
            formatPrice(c.saltYeastCost),
            color: Colors.orange.shade700,
          ),
        ],
        const Divider(height: 12),
        Row(children: [
          Text(loc.translate('bread_total_label'),
              style: const TextStyle(
                  fontSize: AppText.titleSmall, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${formatPrice(c.grandTotal)} сўм',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: AppText.titleMedium,
                    fontWeight: FontWeight.bold,
                    color: _green)),
          ),
        ]),
        const SizedBox(height: 10),
        OrderCheckoutWalletBanner(
          orderTotal: c.grandTotal,
          walletBalance: c.walletBalance,
          walletApply: c.walletApplyAmount,
          cashDue: c.cashDuePreview,
        ),
      ]),
    );
  }

  static const BreadProduct _empty = BreadProduct(id: 0, name: '', type: '');
}

class _BreadModeChip extends StatelessWidget {
  const _BreadModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
