import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../utils/food_catalog.dart';
import '../controllers/food_controller.dart';
import '../widgets/cart_sheet.dart';
import '../widgets/food_order_sheet.dart';
import '../widgets/product_card.dart';

class FoodScreen extends StatelessWidget {
  const FoodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final c = FoodController(
          ordersRepo: ctx.read<OrdersRepository>(),
          inventoryRepo: ctx.read<InventoryRepository>(),
        );
        unawaited(c.init());
        return c;
      },
      child: const _FoodView(),
    );
  }
}

class _FoodView extends StatelessWidget {
  const _FoodView();

  static String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatQty(double qty, String unit) {
    if (qty == qty.roundToDouble()) return '${qty.toInt()} $unit';
    return '$qty $unit';
  }

  Future<void> _showCart(BuildContext context) async {
    final c = context.read<FoodController>();
    final loc = AppLocalizations.of(context)!;
    if (c.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.translate('cart_empty')),
          duration: const Duration(seconds: 1)));
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CartSheet(
        controller: c,
        onOrder: () {
          Navigator.pop(context);
          _showOrderForm(context);
        },
      ),
    );
  }

  Future<void> _showOrderForm(BuildContext context) async {
    final c = context.read<FoodController>();
    final loc = AppLocalizations.of(context)!;

    // Профил маълумотларини бирваракай юклаймиз — телефон ва манзил аввалдан
    // тўлдирилган бўлсин, фойдаланувчи кейин ҳам таҳрирлай олади.
    //
    // Бирламчи манба — SharedPreferences (тезкор, оффлайн ҳам ишлайди).
    // Иккиламчи — Firestore'даги `users/{uid}.address` (структурaли). Агар
    // SharedPreferences бўш бўлса (масалан, фойдаланувчи манзилни faqat profil
    // saqlash exрanida янги форматда сақлаган бўлса) — Firestore'дан formatted
    // string ишлатамиз.
    final prefs = await SharedPreferences.getInstance();
    var savedPhone = prefs.getString('user_phone') ?? '';
    var savedAddress = prefs.getString('user_address') ?? '';

    if (savedAddress.isEmpty) {
      try {
        final uid = phoneDigits(savedPhone);
        if (uid.length >= 9 && context.mounted) {
          final user = await context.read<UserRepository>().getById(uid);
          if (user != null) {
            if (user.address.isComplete) {
              savedAddress = user.address.formatted;
            } else if (user.addressLegacy.isNotEmpty) {
              savedAddress = user.addressLegacy;
            }
          }
        }
      } catch (_) {
        // Силент — Firestore топилмаса фойдаланувчи қўлда ёзади.
      }
    }

    if (!context.mounted) return;
    final addressCtrl = TextEditingController(text: savedAddress);
    final phoneCtrl = TextEditingController(text: savedPhone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FoodOrderSheet(
        parentContext: context,
        controller: c,
        loc: loc,
        addressCtrl: addressCtrl,
        phoneCtrl: phoneCtrl,
        onAfterSubmit: (root, result, cartSnapshot, totalSnapshot) {
          if (!result.success) {
            if (result.error != null) {
              ScaffoldMessenger.of(root).showSnackBar(
                SnackBar(content: Text(result.error!)),
              );
            }
            c.clearError();
            return;
          }
          if (result.isOffline) {
            ScaffoldMessenger.of(root).showSnackBar(
              SnackBar(
                content: Text(loc.translate('bread_snack_order_saved_offline')),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
            return;
          }
          _showConfirmedDialog(
            root,
            addressCtrl.text.trim(),
            phoneCtrl.text.trim(),
            cartSnapshot,
            totalSnapshot,
          );
        },
      ),
    );
  }

  void _showConfirmedDialog(
    BuildContext context,
    String address,
    String phone,
    Map<int, double> cartSnapshot,
    int totalSnapshot,
  ) {
    final c = context.read<FoodController>();
    final loc = AppLocalizations.of(context)!;

    final buffer = StringBuffer();
    for (final entry in cartSnapshot.entries) {
      final p = c.products.firstWhere(
        (e) => e.id == entry.key,
        orElse: () => FoodCatalog.byId(entry.key),
      );
      final qty = entry.value;
      final price = (p.price * qty).round();
      buffer.writeln(
          '${p.emoji} ${p.name}: ${_formatQty(qty, p.unit)} = ${_formatPrice(price)} сўм');
    }
    final total = totalSnapshot;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 28),
          const SizedBox(width: 8),
          Text(loc.translate('order_confirmed')),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.translate('will_contact_soon'),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12)),
                child: Text(buffer.toString(),
                    style: const TextStyle(fontSize: 12)),
              ),
              const Divider(height: 16),
              Text('📍 $address', style: const TextStyle(fontSize: 12)),
              Text('📞 $phone', style: const TextStyle(fontSize: 12)),
              Text('💰 ${_formatPrice(total)} ${loc.translate("sum")}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            ]),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final url = Uri.parse('tel:$phone');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            icon: const Icon(Icons.phone, size: 18),
            label: Text(loc.translate('call')),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              c.clearCart();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(loc.translate('ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<FoodController>();

    final localizedCategories = <String, String>{
      'Барчаси': loc.translate('all_categories'),
      'Асосий': loc.translate('main_dishes'),
      'Товуқ': loc.translate('chicken'),
      'Балиқ': loc.translate('fish'),
      'Шўрва': loc.translate('soups'),
      'Ичимликлар': loc.translate('drinks'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('food_order')),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (c.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    loc
                        .translate('bread_pending_count')
                        .replaceAll('{n}', c.pendingCount.toString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: c.categoryKeys.map((cat) {
                  final isSelected = c.selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => c.selectCategory(cat),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        localizedCategories[cat] ?? cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final products = c.filteredProducts;
                if (constraints.maxWidth >= 700) {
                  final horizontalPad =
                      (constraints.maxWidth * 0.05).clamp(18.0, 56.0);
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                        horizontalPad, 16, horizontalPad, 96),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 330,
                      mainAxisExtent: 340,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: products.length,
                    itemBuilder: (_, index) => ProductCard(
                      product: products[index],
                      controller: c,
                      grid: true,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                  itemCount: products.length,
                  itemBuilder: (_, index) => ProductCard(
                    product: products[index],
                    controller: c,
                  ),
                );
              },
            ),
          ),
        ],
      ),
          if (!c.hasInternet)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loc.translate('bread_offline_banner'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (c.pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            loc
                                .translate('bread_pending_count')
                                .replaceAll('{n}', c.pendingCount.toString()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: c.cartItemCount > 0
          ? FloatingActionButton.extended(
              onPressed: () => _showCart(context),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_basket),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('${c.cartItemCount}',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
              label: Text(
                '${_formatPrice(c.cartTotal)} ${loc.translate("sum")}',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
