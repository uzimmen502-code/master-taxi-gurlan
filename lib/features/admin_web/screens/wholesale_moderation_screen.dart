import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/models/wholesale_seller.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import '../../wholesale/repositories/wholesale_sellers_repository.dart';
import '../services/admin_auth_service.dart';

/// Улгуржи бозор ёки Хитой бозори — admin модерацияси.
/// `JobsModerationScreen`нинг live-stream карта-рўйхат андозаси асосида.
/// Тасдиқ/рад/ўчириш — тўғридан-тўғри ёзув, `firestore.rules`даги admin
/// whitelist-патч орқали чекланади. Бозорни алмаштириш эса — серверда
/// (`adminSetWholesaleProductMarket`, қуйида).
///
/// Иккала бозор битта коллекцияда (`wholesale_products`, `market` билан
/// ажралади) ва сотувчилар рўйхати битта (`wholesale_sellers`). Админда
/// эса иловадаги каби ИККИ алоҳида бўлим (2026-10-07): аввал «Улгуржи
/// бозор» бўлимида Хитой бозори маҳсулотлари аралаш чиқарди. [market]
/// қайси бозорнинг маҳсулотлари кўрсатилишини белгилайди.
class WholesaleModerationScreen extends StatefulWidget {
  const WholesaleModerationScreen({
    super.key,
    this.market = WholesaleProduct.marketWholesale,
    this.leadingTab,
  });

  /// [WholesaleProduct.marketWholesale] ёки [WholesaleProduct.marketChina].
  final String market;

  /// Бўлим бошидаги қўшимча таб. «Улгуржи бозор»да — AVA товарлари
  /// каталоги (эга қарори 2026-10-06: AVA дўкони тўлиқ Улгуржига ўтди;
  /// админдаги алоҳида «AVA дўкони» бўлими 2026-10-07 да шу ерга кўчди).
  final ({String label, Widget child})? leadingTab;

  @override
  State<WholesaleModerationScreen> createState() =>
      _WholesaleModerationScreenState();
}

class _WholesaleModerationScreenState extends State<WholesaleModerationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _sellersRepo = WholesaleSellersRepository();
  final _productsRepo = WholesaleProductsRepository();
  String _productStatusFilter = 'all';

  static const _blue = AppColors.primary;

  bool get _isChina => widget.market == WholesaleProduct.marketChina;

  /// Бир марта очилади: ҳолат филтри (`setState`) ҳар босилганда
  /// Firestore тинглови қайта очилмасин.
  late final Stream<List<WholesaleProduct>> _productsStream =
      _productsRepo.watchAllForAdmin(market: widget.market);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: widget.leadingTab == null ? 2 : 3,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String get _adminId => context.read<AdminAuthService>().phoneDigits ?? '';

  void _showResult(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : null,
        content: Text(text),
      ),
    );
  }

  Future<String?> _promptNote(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Изоҳ (ихтиёрий)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Бекор қилиш'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ─── Сотувчилар ───────────────────────────────────────────────────

  Future<void> _approveSeller(WholesaleSeller s) async {
    try {
      await _sellersRepo.approve(s.phone, adminId: _adminId);
      _showResult('Тасдиқланди: ${s.companyName}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _rejectSeller(WholesaleSeller s) async {
    final note = await _promptNote('«${s.companyName}»ни рад этиш');
    if (note == null || !mounted) return;
    try {
      await _sellersRepo.reject(s.phone, adminId: _adminId, note: note);
      _showResult('Рад этилди: ${s.companyName}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Widget _sellersTab() {
    return StreamBuilder<List<WholesaleSeller>>(
      stream: _sellersRepo.watchAllForAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final all = snap.data ?? const <WholesaleSeller>[];
        int count(String s) => all.where((e) => e.approvalStatus == s).length;
        return Column(children: [
          const _AutoApproveBar(
            settingsField: 'wholesaleSellerAutoApprove',
            onLabel: 'АВТО тасдиқ: ЁҚИҚ — янги сотувчилар дарҳол тасдиқланади',
            offLabel:
                'ҚЎЛДА тасдиқ — янги сотувчилар admin тасдиғини кутади',
          ),
          // Рўйхат битта — бу ердаги тасдиқ/рад иккала бозорга ҳам
          // тегишли. Админ буни билмаса, «Хитой бозори»да рад этган
          // сотувчиси Улгуржидан ҳам ёпилиб қолганига ҳайрон бўлади.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Сотувчилар рўйхати Улгуржи бозор ва Хитой бозори учун '
                  'битта: тасдиқ ёки рад иккала бозорга ҳам тегишли.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              _summaryCard('Жами', all.length, Colors.blueGrey),
              _summaryCard('Кутяпти', count(WholesaleSeller.statusPending),
                  Colors.orange),
              _summaryCard('Тасдиқланган',
                  count(WholesaleSeller.statusApproved), AvaLight.ok),
              _summaryCard(
                  'Рад этилган', count(WholesaleSeller.statusRejected), Colors.red),
            ]),
          ),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('Сотувчи топилмади'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                    itemCount: all.length,
                    itemBuilder: (_, i) => _sellerCard(all[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _sellerCard(WholesaleSeller s) {
    final color = _sellerStatusColor(s.approvalStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _badge(_sellerStatusLabel(s.approvalStatus), color),
            if (s.sellerType.isNotEmpty) ...[
              const SizedBox(width: 8),
              _badge(WholesaleSeller.typeLabel(s.sellerType), Colors.blueGrey),
            ],
            const Spacer(),
            Text(_dateText(s.createdAt),
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(
            s.companyName.isEmpty ? '(Ном йўқ)' : s.companyName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (s.ownerName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(s.ownerName, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 6),
          _meta(Icons.phone, s.phone),
          if (s.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Admin: ${s.adminNote}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: s.isPending ? () => _approveSeller(s) : null,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Тасдиқлаш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tickerShell,
                disabledForegroundColor: AppColors.primaryDark,
              ),
            ),
            OutlinedButton.icon(
              onPressed: s.isPending ? () => _rejectSeller(s) : null,
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Рад этиш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ]),
        ]),
      ),
    );
  }

  // ─── Маҳсулотлар ──────────────────────────────────────────────────

  Future<void> _approveProduct(WholesaleProduct p) async {
    try {
      await _productsRepo.approve(p.id, adminId: _adminId);
      _showResult('Фаоллаштирилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _rejectProduct(WholesaleProduct p) async {
    final note = await _promptNote('«${p.title}»ни ёпиш/рад этиш');
    if (note == null || !mounted) return;
    try {
      await _productsRepo.reject(p.id, adminId: _adminId, note: note);
      _showResult('Ёпилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _deleteProduct(WholesaleProduct p) async {
    final ok = await _confirm(
        'Маҳсулотни ўчириш', '«${p.title}» бутунлай ўчирилади.');
    if (!ok) return;
    try {
      await _productsRepo.delete(p.id);
      _showResult('Ўчирилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  // ─── Бозорни алмаштириш (Улгуржи ↔ Хитой) ─────────────────────────
  //
  // Rules `market`ни ҳеч кимга ўзгартиртирмайди (атайлаб) — шунинг учун
  // СЕРВЕРДА: `adminSetWholesaleProductMarket` (europe-west1). У админлигини
  // текширади, транзакцияда ёзади, қайта босилса иккинчи марта ёзмайди ва
  // ҳар амални `wholesale_market_audit`га туширади (41-қоида). Экран фақат
  // чақиради.

  final Set<String> _movingIds = {};

  Future<void> _callSetMarket(
    WholesaleProduct p, {
    required String market,
    String currency = '',
    int? deliveryDays,
    String reason = '',
  }) async {
    setState(() => _movingIds.add(p.id));
    try {
      final res = await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
          .httpsCallable('adminSetWholesaleProductMarket')
          .call<Object?>({
        'productId': p.id,
        'market': market,
        'currency': currency,
        'deliveryDays': deliveryDays,
        'reason': reason,
      });
      final data = res.data;
      final changed = data is Map && data['changed'] == true;
      final where = market == WholesaleProduct.marketChina
          ? '«Хитой бозори»'
          : '«Улгуржи бозор»';
      _showResult(changed
          ? '«${p.title}» → $where'
          : 'Ўзгариш йўқ — «${p.title}» аллақачон шундай');
    } on FirebaseFunctionsException catch (e) {
      _showResult(_marketErrorText(e), error: true);
    } catch (e) {
      _showResult('Бозорни ўзгартириб бўлмади. Қайта уриниб кўринг.',
          error: true);
      debugPrint('[WholesaleModeration] setMarket $e');
    } finally {
      if (mounted) setState(() => _movingIds.remove(p.id));
    }
  }

  /// Фойдаланувчига матн + диагностик код (25-қоида).
  String _marketErrorText(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map && details['reason'] == 'foreign_currency') {
      return 'Нарх «${details['currency']}» да — Улгуржи бозор фақат сўмда. '
          'Аввал сотувчи нархни сўмда киритсин.';
    }
    switch (e.code) {
      case 'permission-denied':
        return 'Бу амал фақат админ учун (${e.code}).';
      case 'not-found':
        return 'Маҳсулот топилмади — ўчирилган бўлиши мумкин (${e.code}).';
      default:
        return 'Бозорни ўзгартириб бўлмади. Қайта уриниб кўринг (${e.code}).';
    }
  }

  /// Хитой бозорига кўчириш ёки Хитойдаги валюта/муддатни тузатиш.
  Future<void> _moveToChina(WholesaleProduct p) async {
    final r = await showDialog<_ChinaMarketChoice>(
      context: context,
      builder: (_) => _ChinaMarketDialog(product: p),
    );
    if (r == null || !mounted) return;
    await _callSetMarket(
      p,
      market: WholesaleProduct.marketChina,
      currency: r.currency,
      deliveryDays: r.deliveryDays,
      reason: r.reason,
    );
  }

  Future<void> _moveToWholesale(WholesaleProduct p) async {
    // Сервер ҳам рад этади; бу ерда — тушунарли сабаб билан олдиндан.
    if (p.currency.trim().isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Улгуржига кўчириб бўлмайди'),
          content: Text(
            'Нарх «${p.currency.trim()}» да. Улгуржи бозор фақат сўмда — '
            'кўчирилса «${p.basePrice} ${p.currency.trim()}» жимгина '
            '«${p.basePrice} сўм» бўлиб қоларди.\n\n'
            'Аввал сотувчи нархни сўмда киритсин (валютасини «сўм» қилсин).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Тушунарли'),
            ),
          ],
        ),
      );
      return;
    }
    final note = await _promptNote('«${p.title}»ни Улгуржи бозорга кўчириш');
    if (note == null || !mounted) return;
    await _callSetMarket(
      p,
      market: WholesaleProduct.marketWholesale,
      reason: note,
    );
  }

  Widget _productsTab() {
    return StreamBuilder<List<WholesaleProduct>>(
      stream: _productsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final all = snap.data ?? const <WholesaleProduct>[];
        final filtered = _productStatusFilter == 'all'
            ? all
            : all.where((p) => p.status == _productStatusFilter).toList();
        int count(String s) => all.where((e) => e.status == s).length;
        return Column(children: [
          // `settings/app` даги битта майдон — иккала бозор учун умумий.
          const _AutoApproveBar(
            settingsField: 'wholesaleProductAutoApprove',
            onLabel: 'АВТО тасдиқ: ЁҚИҚ — янги маҳсулотлар дарҳол фаол '
                '(Улгуржи ва Хитой бозори учун битта созлама)',
            offLabel: 'ҚЎЛДА тасдиқ — янги маҳсулотлар «Кутилмоқда»га '
                'тушади (Улгуржи ва Хитой бозори учун битта созлама)',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              _summaryCard('Жами', all.length, Colors.blueGrey),
              _summaryCard('Кутяпти', count(WholesaleProduct.statusPending),
                  Colors.orange),
              _summaryCard(
                  'Фаол', count(WholesaleProduct.statusActive), AvaLight.ok),
              _summaryCard('Ёпилган', count(WholesaleProduct.statusInactive),
                  Colors.blueGrey),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(spacing: 8, children: [
              for (final item in const [
                ('all', 'Барчаси'),
                (WholesaleProduct.statusPending, 'Кутяпти'),
                (WholesaleProduct.statusActive, 'Фаол'),
                (WholesaleProduct.statusInactive, 'Ёпилган'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _productStatusFilter == item.$1,
                  onSelected: (_) =>
                      setState(() => _productStatusFilter = item.$1),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Маҳсулот топилмади'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _productCard(filtered[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _productCard(WholesaleProduct p) {
    final color = _productStatusColor(p.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _badge(_productStatusLabel(p.status), color),
            // Бозор белгиси энди керак эмас: ҳар бўлим фақат ўз бозорини
            // кўрсатади ([WholesaleModerationScreen.market]).
            const Spacer(),
            Text(_dateText(p.createdAt),
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.imageUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  p.imageUrls.first,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.title.isEmpty ? '(Ном йўқ)' : p.title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  p.priceTiers.length > 1
                      ? p.priceTiers
                          .map((t) => t.label(p.unit, p.currencyLabel))
                          .join(' · ')
                      : 'Нарх: ${p.basePrice} ${p.currencyLabel}'
                          ' · МОҚ: ${p.moq} ${p.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          _meta(Icons.storefront, p.sellerCompanyName.isEmpty
              ? 'Сотувчи номаълум'
              : p.sellerCompanyName),
          if (_isChina) ...[
            const SizedBox(height: 4),
            _meta(
              Icons.local_shipping_outlined,
              (p.deliveryDays ?? 0) > 0
                  ? 'Етказиш: ${p.deliveryDays} кун'
                  : 'Етказиш муддати кўрсатилмаган',
            ),
          ],
          if (p.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Admin: ${p.adminNote}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: p.isPending ? () => _approveProduct(p) : null,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Фаоллаштириш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tickerShell,
                disabledForegroundColor: AppColors.primaryDark,
              ),
            ),
            OutlinedButton.icon(
              onPressed: p.isActive || p.isPending
                  ? () => _rejectProduct(p)
                  : null,
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Ёпиш/Рад этиш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
            // Бозорни алмаштириш — нотўғри жойда турган маҳсулот учун.
            if (_isChina) ...[
              OutlinedButton.icon(
                onPressed:
                    _movingIds.contains(p.id) ? null : () => _moveToChina(p),
                icon: const Icon(Icons.currency_exchange, size: 18),
                label: const Text('Валюта / муддат'),
              ),
              OutlinedButton.icon(
                onPressed: _movingIds.contains(p.id)
                    ? null
                    : () => _moveToWholesale(p),
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Улгуржига кўчириш'),
              ),
            ] else
              OutlinedButton.icon(
                onPressed:
                    _movingIds.contains(p.id) ? null : () => _moveToChina(p),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Хитой бозорига кўчириш'),
              ),
            OutlinedButton.icon(
              onPressed: () => _deleteProduct(p),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Ўчириш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ]),
        ]),
      ),
    );
  }

  // ─── Умумий виджетлар ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final leading = widget.leadingTab;
    return Column(children: [
      _header(),
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabCtrl,
          labelColor: _blue,
          indicatorColor: _blue,
          tabs: [
            if (leading != null) Tab(text: leading.label),
            Tab(
              text: _isChina ? '📦 Маҳсулотлар' : '📦 Сотувчилар товарлари',
            ),
            const Tab(text: '🧾 Сотувчилар'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            if (leading != null) leading.child,
            _productsTab(),
            _sellersTab(),
          ],
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            // Иловадаги хизмат белгиси билан бир хил.
            _isChina ? Icons.local_shipping_outlined : Icons.warehouse_outlined,
            color: _blue,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isChina
                    ? 'ХИТОЙ БОЗОРИ — назорати'
                    : 'УЛГУРЖИ БОЗОР — назорати',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                _isChina
                    ? 'Хитой бозори маҳсулотларини модерация қилиш'
                    : 'AVA товарлари каталоги, сотувчилар товарлари ва '
                        'сотувчиларни тасдиқлаш',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Text('$value',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style:
              TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: Colors.black45),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(color: Colors.black54)),
    ]);
  }
}

String _dateText(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

Color _sellerStatusColor(String status) {
  switch (status) {
    case WholesaleSeller.statusPending:
      return Colors.orange;
    case WholesaleSeller.statusApproved:
      return AppColors.primary;
    case WholesaleSeller.statusRejected:
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

String _sellerStatusLabel(String status) {
  switch (status) {
    case WholesaleSeller.statusPending:
      return 'Кутяпти';
    case WholesaleSeller.statusApproved:
      return 'Тасдиқланган';
    case WholesaleSeller.statusRejected:
      return 'Рад этилган';
    default:
      return status;
  }
}

Color _productStatusColor(String status) {
  switch (status) {
    case WholesaleProduct.statusPending:
      return Colors.orange;
    case WholesaleProduct.statusActive:
      return AppColors.primary;
    case WholesaleProduct.statusInactive:
      return Colors.blueGrey;
    default:
      return Colors.blueGrey;
  }
}

String _productStatusLabel(String status) {
  switch (status) {
    case WholesaleProduct.statusPending:
      return 'Кутяпти';
    case WholesaleProduct.statusActive:
      return 'Фаол';
    case WholesaleProduct.statusInactive:
      return 'Ёпилган';
    default:
      return status;
  }
}

/// `settings/app.{settingsField}` — ҚЎЛДА / АВТО тасдиқ (`JobsModerationScreen`
/// даги `_JobsAutoApproveBar` андозаси, лекин CF ўрнига тўғридан-тўғри ёзув —
/// `settings/{docId}` учун `isAdmin()` рухсати аллақачон мавжуд).
class _AutoApproveBar extends StatefulWidget {
  const _AutoApproveBar({
    required this.settingsField,
    required this.onLabel,
    required this.offLabel,
  });

  final String settingsField;
  final String onLabel;
  final String offLabel;

  @override
  State<_AutoApproveBar> createState() => _AutoApproveBarState();
}

class _AutoApproveBarState extends State<_AutoApproveBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('app').set({
        widget.settingsField: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('settings').doc('app').snapshots(),
      builder: (context, snap) {
        final auto = snap.data?.data()?[widget.settingsField] == true;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? AvaLight.okSoft : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: auto ? AvaLight.ok : Colors.orange.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              auto ? Icons.flash_on : Icons.admin_panel_settings,
              color: auto ? AvaLight.ok : Colors.orange.shade800,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                auto ? widget.onLabel : widget.offLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: auto ? AvaLight.ok : Colors.orange.shade900,
                ),
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              OutlinedButton(
                onPressed: auto ? () => _setAuto(false) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('ҚЎЛДА', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: auto ? null : () => _setAuto(true),
                icon: const Icon(Icons.flash_on, size: 16),
                label: const Text('АВТО', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}

/// Хитой бозори учун танлов: валюта, етказиш муддати, сабаб.
class _ChinaMarketChoice {
  const _ChinaMarketChoice({
    required this.currency,
    required this.deliveryDays,
    required this.reason,
  });

  final String currency;
  final int? deliveryDays;
  final String reason;
}

/// «Хитой бозорига кўчириш» / «Валюта / муддат» ойнаси.
///
/// Валюталар — сотувчининг Хитой формасидагидек ('' = сўм, `$`, `¥`).
/// Нарх РАҚАМЛАРИ ўзгармайди: админ фақат улар қайси валютада эканини
/// белгилайди (масалан 2026-10-07 даги трактор: 3800 — долларда).
class _ChinaMarketDialog extends StatefulWidget {
  const _ChinaMarketDialog({required this.product});

  final WholesaleProduct product;

  @override
  State<_ChinaMarketDialog> createState() => _ChinaMarketDialogState();
}

class _ChinaMarketDialogState extends State<_ChinaMarketDialog> {
  static const _currencies = <(String, String)>[
    ('\$', '\$ доллар'),
    ('¥', '¥ юань'),
    ('', 'сўм'),
  ];

  late String _currency;
  late final TextEditingController _days;
  final _reason = TextEditingController();
  String? _daysError;

  bool get _alreadyChina => widget.product.isChina;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    // Хитойда — жорий валюта; Улгуржидан кўчаётганда — доллар (Хитой
    // бозоридаги товарларнинг аксарияти шу; админ ўзгартира олади).
    _currency = _alreadyChina ? p.currency.trim() : '\$';
    _days = TextEditingController(
      text: (p.deliveryDays ?? 0) > 0 ? '${p.deliveryDays}' : '',
    );
  }

  @override
  void dispose() {
    _days.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _days.text.trim();
    int? days;
    if (raw.isNotEmpty) {
      days = int.tryParse(raw);
      if (days == null || days < 1 || days > 365) {
        setState(() => _daysError = '1–365 кун');
        return;
      }
    }
    Navigator.pop(
      context,
      _ChinaMarketChoice(
        currency: _currency,
        deliveryDays: days,
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final tiers =
        p.priceTiers.map((t) => '${t.minQty}+: ${t.price}').join(' · ');
    return AlertDialog(
      title: Text(_alreadyChina
          ? '«${p.title}» — валюта ва муддат'
          : '«${p.title}» → Хитой бозори'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Нарх поғоналари: $tiers',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Рақамлар ўзгармайди — улар қайси валютада эканини танланг.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final c in _currencies)
                ChoiceChip(
                  label: Text(c.$2),
                  selected: _currency == c.$1,
                  onSelected: (_) => setState(() => _currency = c.$1),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Етказиш муддати, кун (ихтиёрий)',
                errorText: _daysError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Сабаб (audit учун, ихтиёрий)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Бекор қилиш'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_alreadyChina ? 'Сақлаш' : 'Кўчириш'),
        ),
      ],
    );
  }
}
