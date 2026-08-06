import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/user_repository.dart';
import '../../../widgets/order_checkout_wallet_banner.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../ava_store_colors.dart';
import '../controllers/platform_store_controller.dart';
import 'platform_cross_sell_sheet.dart';

/// Сават: товарлар + жами (ёпишган) + буюртма.
class PlatformCartSheet extends StatefulWidget {
  const PlatformCartSheet({super.key});

  @override
  State<PlatformCartSheet> createState() => _PlatformCartSheetState();
}

class _PlatformCartSheetState extends State<PlatformCartSheet> {
  static const _deep = AvaStoreColors.deep;
  static const _brand = AvaStoreColors.brand;

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

    // Озиқ/но-озиқ аралаштириш таклифи (агар сават бир турда бўлса).
    if (c.suggestOppositeKind != null) {
      final go = await showPlatformCrossSellSheet(context);
      if (!go || !mounted) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString('user_phone') ?? '').trim();
    if (phone.isEmpty || phoneDigits(phone).length < 9) {
      return _showError(loc.translate('bread_error_phone_invalid'));
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          context.tr('platform_store_checkout'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AvaStoreColors.ink,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AvaStoreColors.soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AvaStoreColors.border),
              ),
              child: Text(
                '${context.tr('platform_store_pay_total')}: '
                '${formatPrice(c.grandTotal)} ${loc.translate('sum')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: AvaStoreColors.deep,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OrderCheckoutWalletBanner(
              orderTotal: c.grandTotal,
              walletBalance: c.walletBalance,
              useWallet: c.useWallet,
              onUseWalletChanged: c.setUseWallet,
              walletApply: c.walletApplyAmount,
              cashDue: c.cashDuePreview,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr('platform_store_checkout_hint'),
              style: const TextStyle(fontSize: 12.5, color: AvaStoreColors.muted),
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
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: AvaStoreColors.onBrand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              context.tr('platform_store_checkout'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
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
          backgroundColor: _deep,
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
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: AvaStoreColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AvaStoreColors.softFill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('platform_store_cart_title'),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AvaStoreColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    c.clearCart();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: _deep),
                  child: Text(
                    context.tr('platform_store_clear_cart'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AvaStoreColors.brand.withValues(alpha: 0.35)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              itemCount: c.cart.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = c.cart.entries.elementAt(i);
                return _CartLine(id: e.key, qty: e.value);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
            decoration: BoxDecoration(
              color: AvaStoreColors.surface,
              boxShadow: [
                BoxShadow(
                  color: AvaStoreColors.deep.withValues(alpha: 0.1),
                  blurRadius: 14,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      context.tr('platform_store_products_total'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: AvaStoreColors.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${formatPrice(c.cartTotal)} ${loc.translate('sum')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AvaStoreColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('platform_store_delivery_fee'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: AvaStoreColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr('platform_store_delivery_fee_hint'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: AvaStoreColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      c.deliveryFee > 0
                          ? '+${formatPrice(c.deliveryFee)} ${loc.translate('sum')}'
                          : '0 ${loc.translate('sum')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AvaStoreColors.deep,
                      ),
                    ),
                  ],
                ),
                if (c.deliveryFeePercent > 0) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context
                          .tr('platform_store_delivery_fee_pct')
                          .replaceAll('{pct}', _fmtPct(c.deliveryFeePercent)),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AvaStoreColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: AvaStoreColors.brand.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      context.tr('platform_store_pay_total'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AvaStoreColors.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${formatPrice(c.grandTotal)} ${loc.translate('sum')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _deep,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed:
                        (_isSending || c.isSubmitting) ? null : _sendOrder,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: AvaStoreColors.onBrand,
                      disabledBackgroundColor: AvaStoreColors.softFill,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: (_isSending || c.isSubmitting)
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AvaStoreColors.onBrand,
                            ),
                          )
                        : Text(
                            context.tr('platform_store_checkout'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
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
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<PlatformStoreController>();
    final p = c.productOf(id);
    if (p == null) return const SizedBox.shrink();
    final line = p.price * qty;
    final unitPrice = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(p.price),
        );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AvaStoreColors.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AvaStoreColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: ColoredBox(
                color: AvaStoreColors.surface,
                child: _Thumb(url: p.coverImageUrl),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AvaStoreColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unitPrice,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AvaStoreColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatPrice(line)} ${loc.translate('sum')}',
                  style: const TextStyle(
                    color: AvaStoreColors.deep,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: AvaStoreColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AvaStoreColors.brand, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TinyQty(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    c.decrease(id);
                  },
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                _TinyQty(
                  icon: Icons.add_rounded,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    c.increase(id);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyQty extends StatelessWidget {
  const _TinyQty({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AvaStoreColors.brand,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 36,
          child: Icon(icon, size: 18, color: AvaStoreColors.onBrand),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: BoxFit.contain);
    }
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.contain,
        memCacheWidth: 200,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AvaStoreColors.deep,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Icon(
          Icons.shopping_bag_outlined,
          color: AvaStoreColors.muted,
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
    }
    return const Icon(
      Icons.shopping_bag_outlined,
      color: AvaStoreColors.muted,
    );
  }
}

String _fmtPct(double pct) {
  if (pct == pct.roundToDouble()) return '${pct.round()}';
  return pct.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}
