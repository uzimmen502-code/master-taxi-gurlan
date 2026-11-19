import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../services/admin_callable.dart';

/// «Чегирмалар» (эга 2026-11-19/20), икки таб:
///  1. «Сотувчилар сўровлари» — `promoState.status == 'pending'` (битта майдон тенглиги — автоматик индекс);
///     тасдиқ/рад — ФАҚАТ `adminModeratePromo` (транзакция + admin_audit + сотувчига хабар). Тасдиқда сервер
///     нарх майдонларини чегирмали қийматга ёзади — харидор шуни тўлайди.
///  2. «AVA товарлари» — `platform_products` ва AVA'нинг ulgurji товарлари (`sellerCompanyName == 'AVA'`, `pp_*`,
///     tools/migrate_platform_to_owner_wholesale.js) — админ «−N%» ни бевосита қўяди/олади (`adminSetProductDiscount`).
///     Иккала коллекцияда алоҳида нарх бор — керак бўлса иккаласига ҳам қўйилади.
class PromoModerationScreen extends StatelessWidget {
  const PromoModerationScreen({super.key, this.firestore, this.functions});

  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Сотувчилар сўровлари'), Tab(text: 'AVA товарлари')]),
        Expanded(
          child: TabBarView(children: [
            _SellerRequestsTab(firestore: firestore, functions: functions),
            AvaDiscountsTab(firestore: firestore, functions: functions),
          ]),
        ),
      ]),
    );
  }
}

String _date(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

Future<Map<String, dynamic>> _call(FirebaseFunctions? f, String name, Map<String, dynamic> payload) =>
    AdminCallable(f ?? FirebaseFunctions.instance).call(name, payload);

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class PromoModItem {
  const PromoModItem({required this.collection, required this.id, required this.title, required this.percent,
    required this.price, required this.newPrice, this.until, this.photo = ''});
  final String collection;
  final String id;
  final String title;
  final int percent;
  final int price;
  final int newPrice;
  final DateTime? until;
  final String photo;

  static PromoModItem fromRaw(String collection, String id, Map<String, dynamic> d) {
    final s = d['promoState'] is Map ? d['promoState'] as Map : const {};
    final photos = collection == 'wholesale_products' ? d['imageUrls'] : d['photoUrls'];
    int i(Object? v) => v is int ? v : 0;
    return PromoModItem(
      collection: collection,
      id: id,
      title: (d['title'] as String?)?.trim() ?? '',
      percent: i(s['percent']),
      price: i(s['price']),
      newPrice: i(s['newPrice']),
      until: s['until'] is Timestamp ? (s['until'] as Timestamp).toDate() : null,
      photo: photos is List && photos.isNotEmpty && photos.first is String ? photos.first as String : '',
    );
  }
}

class _SellerRequestsTab extends StatefulWidget {
  const _SellerRequestsTab({this.firestore, this.functions});
  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;

  @override
  State<_SellerRequestsTab> createState() => _SellerRequestsTabState();
}

class _SellerRequestsTabState extends State<_SellerRequestsTab> {
  static const _collections = ['tv_shop_items', 'wholesale_products'];
  late Future<List<PromoModItem>> _future = _load();
  final Set<String> _busy = {};

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<List<PromoModItem>> _load() async {
    final out = <PromoModItem>[];
    for (final c in _collections) {
      final snap = await _db.collection(c).where('promoState.status', isEqualTo: 'pending').limit(100).get();
      out.addAll(snap.docs.map((d) => PromoModItem.fromRaw(c, d.id, d.data())));
    }
    return out;
  }

  Future<void> _decide(PromoModItem it, bool approve) async {
    String? reason;
    if (!approve) {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Рад этиш сабаби'),
          content: TextField(controller: ctrl, maxLength: 300, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Рад этиш')),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    setState(() => _busy.add(it.id));
    try {
      final res = await _call(widget.functions, 'adminModeratePromo', {
        'collection': it.collection,
        'id': it.id,
        'decision': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      });
      if (!mounted) return;
      final why = res['reason'] != null ? ' (${res['reason']})' : '';
      _snack(context, 'Натижа: ${res['status']}$why');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${e is AdminCallableException ? e.code : 'INTERNAL'}');
    } finally {
      if (mounted) setState(() => _busy.remove(it.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PromoModItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return Center(child: TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Қайта юклаш')));
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) return const Center(child: Text('Кутилаётган чегирма йўқ'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            final busy = _busy.contains(it.id);
            return ListTile(
              key: ValueKey('promo_mod_${it.id}'),
              leading: it.photo.isEmpty ? const Icon(Icons.image_outlined) : Image.network(it.photo, width: 48, height: 48, fit: BoxFit.cover),
              title: Text('−${it.percent}%  ${it.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${it.collection == 'wholesale_products' ? 'Улгуржи' : 'Дўкон/бозор'} · '
                  '${formatPrice(it.price)} → ${formatPrice(it.newPrice)} · ${_date(it.until)} гача'),
              trailing: Wrap(spacing: 4, children: [
                IconButton(tooltip: 'Тасдиқлаш', onPressed: busy ? null : () => _decide(it, true), icon: const Icon(Icons.check_circle, color: Colors.green)),
                IconButton(tooltip: 'Рад этиш', onPressed: busy ? null : () => _decide(it, false), icon: const Icon(Icons.cancel, color: Colors.red)),
              ]),
            );
          },
        );
      },
    );
  }
}

/// AVA товари қатори (тестланади).
class AvaPromoRow {
  const AvaPromoRow({required this.collection, required this.id, required this.title, required this.price,
    this.percent = 0, this.basePrice = 0, this.until});
  final String collection;
  final String id;
  final String title;
  final int price;
  final int percent;
  final int basePrice;
  final DateTime? until;

  bool get hasDiscount => percent > 0 && basePrice > 0;

  static AvaPromoRow fromRaw(String collection, String id, Map<String, dynamic> d) {
    final p = d['promo'] is Map ? d['promo'] as Map : const {};
    int i(Object? v) => v is int ? v : 0;
    int price;
    if (collection == 'wholesale_products') {
      final tiers = d['priceTiers'] is List ? d['priceTiers'] as List : const [];
      price = tiers.isNotEmpty && tiers.first is Map ? i((tiers.first as Map)['price']) : 0;
    } else {
      price = i(d['price']);
    }
    return AvaPromoRow(
      collection: collection,
      id: id,
      title: ((d['name'] ?? d['title']) as String?)?.trim() ?? id,
      price: price,
      percent: p['kind'] == 'discount' ? i(p['percent']) : 0,
      basePrice: i(p['basePrice']),
      until: p['until'] is Timestamp ? (p['until'] as Timestamp).toDate() : null,
    );
  }
}

class AvaDiscountsTab extends StatefulWidget {
  const AvaDiscountsTab({super.key, this.firestore, this.functions});
  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;

  @override
  State<AvaDiscountsTab> createState() => _AvaDiscountsTabState();
}

class _AvaDiscountsTabState extends State<AvaDiscountsTab> {
  late Future<List<AvaPromoRow>> _future = _load();
  final Set<String> _busy = {};

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<List<AvaPromoRow>> _load() async {
    final pl = await _db.collection('platform_products').limit(200).get();
    final ws = await _db.collection('wholesale_products').where('sellerCompanyName', isEqualTo: 'AVA').limit(200).get();
    return [
      ...pl.docs.map((d) => AvaPromoRow.fromRaw('platform_products', d.id, d.data())),
      ...ws.docs.map((d) => AvaPromoRow.fromRaw('wholesale_products', d.id, d.data())),
    ];
  }

  Future<void> _set(AvaPromoRow r) async {
    final pct = TextEditingController(text: '10');
    final days = TextEditingController(text: '7');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Чегирма: ${r.title}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: pct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Фоиз (1–90)')),
          TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Неча кун (1–30)')),
          const SizedBox(height: 8),
          const Text('Нарх охирги 30 кунда ≥ 7 кун ўзгармаган бўлиши шарт (сервер текширади).', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Қўйиш')),
        ],
      ),
    );
    if (ok != true) return;
    final p = int.tryParse(pct.text.trim());
    final d = int.tryParse(days.text.trim());
    if (p == null || d == null || d < 1 || d > 30) {
      if (mounted) _snack(context, 'Хато: PERCENT_OR_DAYS_INVALID');
      return;
    }
    // ≤ 30 кун серверда `now`дан ўлчанади — 5 дақиқа захира.
    final untilMs = DateTime.now().add(Duration(days: d)).subtract(d == 30 ? const Duration(minutes: 5) : Duration.zero).millisecondsSinceEpoch;
    await _run(r, {'action': 'set', 'percent': p, 'untilMs': untilMs});
  }

  Future<void> _run(AvaPromoRow r, Map<String, dynamic> extra) async {
    setState(() => _busy.add(r.id));
    try {
      final res = await _call(widget.functions, 'adminSetProductDiscount', {'collection': r.collection, 'id': r.id, ...extra});
      if (!mounted) return;
      _snack(context, res['newPrice'] != null ? 'Янги нарх: ${formatPrice(res['newPrice'] as int)}' : 'Бажарилди');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${e is AdminCallableException ? e.code : 'INTERNAL'}');
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AvaPromoRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) {
          return Center(child: TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Қайта юклаш')));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const Center(child: Text('AVA товарлари топилмади'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            final busy = _busy.contains(r.id);
            final where = r.collection == 'platform_products' ? 'AVA дўкони' : 'Улгуржи (AVA)';
            return ListTile(
              key: ValueKey('ava_promo_${r.collection}_${r.id}'),
              title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(r.hasDiscount
                  ? '$where · −${r.percent}%: ${formatPrice(r.basePrice)} → ${formatPrice(r.price)} · ${_date(r.until)} гача'
                  : '$where · ${formatPrice(r.price)}'),
              trailing: r.hasDiscount
                  ? TextButton(onPressed: busy ? null : () => _run(r, {'action': 'clear'}), child: const Text('Олиб ташлаш'))
                  : TextButton(onPressed: busy ? null : () => _set(r), child: const Text('−% қўйиш')),
            );
          },
        );
      },
    );
  }
}
