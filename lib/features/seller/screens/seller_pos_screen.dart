import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/bread_product.dart';
import '../../../models/food_product.dart';
import '../../../models/order_model.dart';
import '../controllers/seller_pos_controller.dart';

/// Sotuvchi mini-kassa — Tezkor + Buyurtmalar.
class SellerPosScreen extends StatelessWidget {
  const SellerPosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SellerPosController(),
      child: const _SellerPosView(),
    );
  }
}

class _SellerPosView extends StatelessWidget {
  const _SellerPosView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SellerPosController>();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: const Text('Sotuv'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: InkWell(
                onTap: () => _showShiftSheet(context, c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    c.shiftLoading
                        ? '…'
                        : 'Bugun: ${formatPrice(c.sessionTotal)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _MainTabs(c: c),
          Expanded(
            child: c.mainTab == SellerMainTab.tezkor
                ? _TezkorBody(c: c)
                : _OrdersBody(c: c),
          ),
        ],
      ),
    );
  }
}

void _showShiftSheet(BuildContext context, SellerPosController c) {
  unawaited(c.refreshShiftSummary());
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return ListenableBuilder(
        listenable: c,
        builder: (_, __) {
          final s = c.shiftSummary;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugungi smena${s != null ? ' · ${s.dateKey}' : ''}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (c.shiftLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (c.shiftLoadError != null)
                  Text(c.shiftLoadError!,
                      style: TextStyle(color: Colors.red.shade700))
                else if (s == null)
                  const Text('Ma\'lumot yo\'q')
                else ...[
                  _ShiftRow('Jami', formatPrice(s.total)),
                  _ShiftRow('Sotuvlar', '${s.count}'),
                  _ShiftRow('Tezkor', '${s.posCount}'),
                  _ShiftRow('Olib ketish', '${s.pickupCount}'),
                  _ShiftRow('Naqd', formatPrice(s.cashPaid)),
                  _ShiftRow('Hamyon', formatPrice(s.walletPaid)),
                  if (s.changeCredit > 0)
                    _ShiftRow('Qaytim', formatPrice(s.changeCredit)),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(value,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Future<void> _showSaleReceipt(
  BuildContext context,
  SellerPosController c,
) async {
  final receipt = c.lastReceipt;
  if (receipt == null) return;
  final r = receipt.result;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(receipt.pickup ? 'Olib ketish to\'lovi' : 'Sotuv cheki'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (receipt.customerPhone.isNotEmpty)
                Text('Mijoz: ${receipt.customerPhone}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              if (r.orderId.isNotEmpty)
                Text(
                  '#${r.orderId.length > 8 ? r.orderId.substring(0, 8) : r.orderId}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              const SizedBox(height: 8),
              ...receipt.lines.map(
                (l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l.emoji.isNotEmpty ? '${l.emoji} ' : ''}${l.name} × ${l.qty % 1 == 0 ? l.qty.toInt() : l.qty}',
                        ),
                      ),
                      Text(formatPrice(l.lineTotal)),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _ShiftRow('Jami', '${formatPrice(r.total)} so\'m'),
              _ShiftRow('Naqd', formatPrice(r.cashPaid)),
              if (r.walletPaid > 0)
                _ShiftRow('Hamyon', formatPrice(r.walletPaid)),
              if (r.changeCredit > 0)
                _ShiftRow('Qaytim', formatPrice(r.changeCredit)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class _MainTabs extends StatelessWidget {
  const _MainTabs({required this.c});
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _TabBtn(
              label: 'Tezkor',
              selected: c.mainTab == SellerMainTab.tezkor,
              onTap: () => c.setMainTab(SellerMainTab.tezkor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TabBtn(
              label: 'Buyurtmalar',
              selected: c.mainTab == SellerMainTab.orders,
              badge: c.queueBadgeCount,
              onTap: () => c.setMainTab(SellerMainTab.orders),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorderMuted,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? AppColors.primaryDark : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TezkorBody extends StatelessWidget {
  const _TezkorBody({required this.c});
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final ultra = constraints.maxWidth >= 1100;
        final grid = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Mahsulot qidirish',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: c.setProductSearch,
              ),
            ),
            Expanded(child: _ProductGrid(c: c)),
          ],
        );
        if (wide) {
          final cartW = ultra
              ? (constraints.maxWidth * 0.34).clamp(360.0, 440.0)
              : 360.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: grid),
              SizedBox(
                width: cartW,
                child: Material(
                  elevation: 4,
                  color: Colors.white,
                  child: SafeArea(
                    left: false,
                    child: _CartPanel(c: c),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: grid),
            Material(
              elevation: 8,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.48,
                  ),
                  child: _CartPanel(c: c),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({required this.c});
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    if (c.payingOrder != null) {
      return Material(
        color: Colors.white,
        child: SafeArea(child: _CartPanel(c: c, pickupMode: true)),
      );
    }

    final orders = c.filteredPickupOrders;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Telefon yoki ism',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: c.setOrderSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _FilterChip(
                label: 'Tayyor${c.readyBadgeCount > 0 ? ' (${c.readyBadgeCount})' : ''}',
                selected: c.orderFilter == SellerOrderFilter.ready,
                onTap: () => c.setOrderFilter(SellerOrderFilter.ready),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Kutilmoqda${c.waitingBadgeCount > 0 ? ' (${c.waitingBadgeCount})' : ''}',
                selected: c.orderFilter == SellerOrderFilter.waiting,
                onTap: () => c.setOrderFilter(SellerOrderFilter.waiting),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Hammasi${c.queueBadgeCount > 0 ? ' (${c.queueBadgeCount})' : ''}',
                selected: c.orderFilter == SellerOrderFilter.all,
                onTap: () => c.setOrderFilter(SellerOrderFilter.all),
              ),
            ],
          ),
        ),
        if (c.ordersLoadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(c.ordersLoadError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        if (c.lastError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(c.lastError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text(
                    'Buyurtma yo\'q',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _OrderCard(order: orders[i], c: c),
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.c});
  final OrderModel order;
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    final paid = order.effectivePayment == 'paid';
    final ready = order.effectiveFulfillment == 'ready';
    final waiting = !paid && !ready;

    Color chipColor;
    String chipLabel;
    if (paid) {
      chipColor = Colors.grey;
      chipLabel = 'To\'landi';
    } else if (ready) {
      chipColor = AppColors.primary;
      chipLabel = 'Tayyor';
    } else {
      chipColor = Colors.orange;
      chipLabel = 'Kutilmoqda';
    }

    final itemsText = order.items
        .map((it) => '${it.name} ×${it.qty}')
        .join(', ');
    final waitLabel = _waitLabel(order.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  chipLabel,
                  style: TextStyle(
                    color: chipColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (waitLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  waitLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                paid ? 'To\'langan' : 'To\'lanmagan',
                style: TextStyle(
                  fontSize: 12,
                  color: paid ? Colors.grey : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${order.userName.isNotEmpty ? order.userName : 'Mijoz'}'
            '${order.userPhone.isNotEmpty ? ' · ${order.userPhone}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (itemsText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(itemsText,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
          const SizedBox(height: 4),
          Text(
            '${formatPrice(order.total)} so\'m',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
              fontSize: 16,
            ),
          ),
          if (!paid) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (order.userPhone.isNotEmpty)
                  IconButton(
                    tooltip: 'Qo\'ng\'iroq',
                    onPressed: () => callPhone(order.userPhone),
                    icon: const Icon(Icons.phone_outlined),
                  ),
                const Spacer(),
                if (waiting)
                  FilledButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            final ok = await c.markReady(order);
                            if (!context.mounted || ok) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(c.lastError ?? 'Xato'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                    ),
                    child: const Text('Tayyor qilish'),
                  ),
                if (ready)
                  FilledButton(
                    onPressed: c.busy ? null : () => c.startPayingOrder(order),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('To\'lov'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _waitLabel(DateTime? createdAt) {
    if (createdAt == null) return '';
    final mins = DateTime.now().difference(createdAt).inMinutes;
    if (mins < 1) return 'hozir';
    if (mins < 60) return '$mins daq';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h soat' : '$h soat $m daq';
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.c});
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxWidth >= 1100
            ? 200.0
            : (constraints.maxWidth >= 720 ? 180.0 : 160.0);
        final tiles = <Widget>[
          ...c.filteredFoodProducts.map((p) => _FoodTile(product: p, c: c)),
          ...c.filteredBreadProducts.map((p) => _BreadTile(product: p, c: c)),
        ];
        if (tiles.isEmpty) {
          return Center(
            child: Text(
              c.productSearch.trim().isEmpty
                  ? 'Mahsulotlar yuklanmoqda…'
                  : 'Topilmadi',
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: extent,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) => tiles[i],
        );
      },
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.product, required this.c});
  final FoodProduct product;
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    final stock = c.stockForFood(product);
    final soldOut = stock <= 0;
    return _ProductCard(
      emoji: product.emoji,
      imageUrl: product.imageUrl,
      name: product.name,
      price: product.price,
      stockLabel: stock >= 999999 ? '∞' : '$stock',
      soldOut: soldOut,
      onTap: soldOut ? null : () => c.addFood(product),
    );
  }
}

class _BreadTile extends StatelessWidget {
  const _BreadTile({required this.product, required this.c});
  final BreadProduct product;
  final SellerPosController c;

  @override
  Widget build(BuildContext context) {
    final soldOut = product.isSoldOut;
    final stock = product.totalStock <= 0 ? '∞' : '${product.remaining}';
    return _ProductCard(
      emoji: product.emoji,
      imageUrl: product.imageUrl,
      assetImage: product.image,
      name: product.name,
      price: product.price ?? 0,
      stockLabel: stock,
      soldOut: soldOut,
      onTap: soldOut ? null : () => c.addBread(product),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.emoji,
    required this.name,
    required this.price,
    required this.stockLabel,
    required this.soldOut,
    required this.onTap,
    this.imageUrl = '',
    this.assetImage = '',
  });

  final String emoji;
  final String imageUrl;
  final String assetImage;
  final String name;
  final int price;
  final String stockLabel;
  final bool soldOut;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: soldOut ? Colors.grey.shade200 : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorderMuted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ColoredBox(
                    color: Colors.grey.shade100,
                    child: Opacity(
                      opacity: soldOut ? 0.45 : 1,
                      child: _buildImage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AppText.bodyMedium,
                    color: soldOut ? Colors.grey : Colors.black87,
                  ),
                ),
              ),
              Text(
                '${formatPrice(price)} so\'m',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: soldOut ? Colors.grey : AppColors.primaryDark,
                  fontSize: AppText.titleSmall,
                ),
              ),
              Text(
                'Qoldiq: $stockLabel',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiFallback() =>
      Center(child: Text(emoji, style: const TextStyle(fontSize: 32)));

  Widget _buildImage() {
    final trimmed = imageUrl.trim();
    final mem = decodeDataUrlImageBytes(trimmed);
    if (mem != null && mem.isNotEmpty) {
      return Image.memory(
        mem,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _emojiFallback(),
      );
    }
    var url = trimmed;
    if (url.startsWith('//')) url = 'https:$url';
    if (isHttpImageUrl(url)) {
      return Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _emojiFallback();
        },
        errorBuilder: (_, __, ___) => _emojiFallback(),
      );
    }
    if (assetImage.trim().isNotEmpty) {
      return Image.asset(
        assetImage.trim(),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _emojiFallback(),
      );
    }
    return _emojiFallback();
  }
}

class _CartPanel extends StatefulWidget {
  const _CartPanel({required this.c, this.pickupMode = false});
  final SellerPosController c;
  final bool pickupMode;

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  final _phoneCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  Timer? _phoneDebounce;

  @override
  void initState() {
    super.initState();
    _cashCtrl.text = '${widget.c.cashPaid}';
    if (widget.pickupMode) {
      _phoneCtrl.text = widget.c.customerPhone;
    }
  }

  @override
  void didUpdateWidget(covariant _CartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final want = '${widget.c.cashPaid}';
    if (_cashCtrl.text != want &&
        FocusManager.instance.primaryFocus?.context == null) {
      _cashCtrl.text = want;
    }
  }

  @override
  void dispose() {
    _phoneDebounce?.cancel();
    _phoneCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final pickup = widget.pickupMode && c.payingOrder != null;
    final lines = c.cart.values.toList();
    final total = pickup ? c.payingOrder!.total : c.cartTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pickup
                      ? 'To\'lov · ${c.payingOrder!.userName.isNotEmpty ? c.payingOrder!.userName : 'buyurtma'}'
                      : 'Savat · ${c.cartCount} ta',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppText.titleMedium),
                ),
              ),
              if (pickup)
                TextButton(
                  onPressed: c.busy ? null : c.cancelPayingOrder,
                  child: const Text('Orqaga'),
                )
              else if (lines.isNotEmpty)
                TextButton(
                  onPressed: c.busy ? null : c.clearCart,
                  child: const Text('Tozalash'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: pickup
                ? ListView(
                    children: c.payingOrder!.items
                        .map((it) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(it.name),
                              trailing: Text(
                                '×${it.qty ?? it.count} · ${formatPrice(it.lineTotal > 0 ? it.lineTotal : it.itemTotal)}',
                              ),
                            ))
                        .toList(),
                  )
                : lines.isEmpty
                    ? Center(
                        child: Text(
                          'Mahsulot tanlang',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        itemCount: lines.length,
                        itemBuilder: (_, i) {
                          final l = lines[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${l.emoji} ${l.name}'),
                            subtitle: Text(
                              '${formatPrice(l.unitPrice)} × ${l.qty}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => c.setQty(
                                      l.key,
                                      l.qty -
                                          (l.kind == 'food' ? 0.5 : 1)),
                                ),
                                Text('${l.qty}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => c.setQty(
                                      l.key,
                                      l.qty +
                                          (l.kind == 'food' ? 0.5 : 1)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          const Divider(),
          Text(
            'Jami: ${formatPrice(total)} so\'m',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          if (!pickup)
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mijoz telefoni (ixtiyoriy)',
                hintText: '90 123 45 67',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                suffixIcon: c.walletLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: (v) {
                _phoneDebounce?.cancel();
                _phoneDebounce = Timer(const Duration(milliseconds: 500), () {
                  c.setCustomerPhone(v);
                });
              },
            )
          else
            Text(
              'Mijoz: ${c.customerPhone} · Hamyon: ${formatPrice(c.walletBalance)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          if (!pickup && c.customerPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Hamyon: ${formatPrice(c.walletBalance)} so\'m',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          if (c.walletLoadError != null) ...[
            const SizedBox(height: 4),
            Text(
              c.walletLoadError!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _PayChip(
                label: 'Naqd',
                selected: c.payMode == SellerPayMode.cash,
                onTap: () => c.setPayMode(SellerPayMode.cash),
              ),
              const SizedBox(width: 6),
              _PayChip(
                label: 'Hamyon',
                selected: c.payMode == SellerPayMode.wallet,
                onTap: () => c.setPayMode(SellerPayMode.wallet),
              ),
              const SizedBox(width: 6),
              _PayChip(
                label: 'Aralash',
                selected: c.payMode == SellerPayMode.mixed,
                onTap: () => c.setPayMode(SellerPayMode.mixed),
              ),
            ],
          ),
          if (c.payMode != SellerPayMode.wallet) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _cashCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Naqd olingan',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => c.setCashPaid(int.tryParse(v) ?? 0),
            ),
          ],
          if (c.walletPaid > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Hamyondan: ${formatPrice(c.walletPaid)} · '
                'Naqd: ${formatPrice(c.cashDue)}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
              ),
            ),
          if (c.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                c.lastError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: c.busy || (!pickup && c.cart.isEmpty)
                ? null
                : () async {
                    final result = await c.checkout();
                    if (!context.mounted || result == null) return;
                    await _showSaleReceipt(context, c);
                    if (!context.mounted) return;
                    _cashCtrl.text = '0';
                  },
            child: c.busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('To\'lov · ${formatPrice(total)}'),
          ),
        ],
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
