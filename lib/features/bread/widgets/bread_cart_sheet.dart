import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/bread_extra_product.dart';
import '../../../models/bread_product.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/wallet_payment.dart';
import '../../../widgets/wallet_cash_split_panel.dart';
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
  static const _green = Color(0xFF2E7D32);
  static const _primary = Color(0xFFE65100);

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _cashPaidCtrl = TextEditingController();
  bool _isSending = false;

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
      final eff = WalletPayment.maxDebitFromWallet(c.walletBalance, c.grandTotal);
      final due = (c.grandTotal - eff).clamp(0, 999999999);
      _cashPaidCtrl.text = '$due';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    _cashPaidCtrl.dispose();
    super.dispose();
  }

  int _parseCashPaid() {
    final raw = _cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(raw) ?? 0;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _sendOrder() async {
    final c = context.read<BreadController>();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final addr = _addrCtrl.text.trim();

    if (name.isEmpty) return _showError('Исмингизни киритинг');
    if (phone.isEmpty || phone.length < 9) {
      return _showError('Телефон рақамини тўғри киритинг');
    }
    if (addr.isEmpty) return _showError('Манзилни киритинг');

    final cashPaid = _parseCashPaid();

    setState(() => _isSending = true);

    final result = await c.sendOrder(
      name: name,
      phone: phone,
      address: addr,
      cashPaid: cashPaid,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (!result.success) {
      _showError(result.error ?? 'Хатолик');
      return;
    }

    final isOffline = result.isOffline;
    c.clearCart();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isOffline
          ? '📵 Интернет йўқ. Буюртма сақланди — интернет келганда автоматик юборилади.'
          : '✅ Буюртма юборилди! Тасдиқланса хабар берамиз.'),
      backgroundColor: isOffline ? Colors.orange : _primary,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('🛒 Сават',
                style: TextStyle(
                    fontSize: AppText.titleLarge,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
                onTap: () => Navigator.of(context).pop(),
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
                const Text('📦 Буюртма',
                    style: TextStyle(
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
                    const Expanded(
                      child: Text(
                        '🌿 Қўшимча махсулотлар',
                        style: TextStyle(
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
                      child: const Text(
                        'ИХТИЁРИЙ',
                        style: TextStyle(
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
                            '🎁 ${p.bonusThreshold} дан бошлаб бонус: '
                            '${p.bonusQty} тага ${p.bonusPercent}% чегирма',
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
                _PriceSummary(
                  cashPaidCtrl: _cashPaidCtrl,
                ),
                const SizedBox(height: 16),
                const Text('👤 Маълумотлар',
                    style: TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _inputField(_nameCtrl, '👤 Исм', TextInputType.name),
                const SizedBox(height: 8),
                _inputField(
                    _addrCtrl, '📍 Манзил', TextInputType.streetAddress),
                const SizedBox(height: 8),
                _inputField(_phoneCtrl, '📞 Телефон', TextInputType.phone),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ||
                            !WalletPayment.orderPayableWithAutoWallet(
                              walletBalance: c.walletBalance,
                              orderTotal: c.grandTotal,
                              cashPaid: _parseCashPaid(),
                            )
                        ? null
                        : _sendOrder,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18),
                    label: Text(_isSending ? 'Юборилмоқда...' : 'ТАСДИҚЛАЙМАН',
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
                    'Буюртма юборилгандан кейин тасдиқланса хабар берамиз',
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

  static const _green = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
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
          const Text('Ун ва сут:',
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: _choiceBtn('🏠 Биз қўшамиз', choice == 'ours',
                    () => c.setFlourMilkChoice(product.id, 'ours'))),
            const SizedBox(width: 8),
            Expanded(
                child: _choiceBtn('🧑 Ўзингиз олиб келасиз', choice == 'yours',
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

  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BreadController>();
    final flourG = product.flourG ?? 300;
    final milkMl = product.milkMl ??
        ((product.milkRatio ?? 0.575) * flourG).round();
    final cost = c.flourMilkCost(product, count);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _green.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
          child: Text(
            '🌾 Ун: ${flourG * count}г  🥛 Сут: ${milkMl * count}мл',
            style: const TextStyle(
                fontSize: AppText.labelSmall, color: Colors.grey),
          ),
        ),
        Text('+${formatPrice(cost)} сўм',
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
  const _PriceSummary({
    required this.cashPaidCtrl,
  });

  final TextEditingController cashPaidCtrl;

  static const _green = Color(0xFF2E7D32);

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
    final c = context.watch<BreadController>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.3)),
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
            return _summaryRow('  🌾 Ун+Сут (${p.name})',
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
                '  🎁 Бонус',
                '-${formatPrice(p.discountFor(c.extraProductsCart[p.id] ?? 0))}',
                color: Colors.orange.shade700,
              ),
          ],
        ],
        if (c.saltYeastCost > 0) ...[
          const Divider(height: 12),
          _summaryRow(
            c.cartHasYopishBread
                ? '🧂 Туз · хамиртуруш · дрожа'
                : '🧂 Туз ва дрожа',
            formatPrice(c.saltYeastCost),
            color: Colors.orange.shade700,
          ),
        ],
        const Divider(height: 12),
        Row(children: [
          const Text('💰 Жами:',
              style: TextStyle(
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
        WalletCashSplitPanel(
          orderTotal: c.grandTotal,
          walletBalance: c.walletBalance,
          cashPaidCtrl: cashPaidCtrl,
        ),
      ]),
    );
  }

  static const BreadProduct _empty = BreadProduct(id: 0, name: '', type: '');
}
