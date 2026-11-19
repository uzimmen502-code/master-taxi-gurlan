import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../services/admin_callable.dart';

/// «Чегирмалар модерацияси» (эга 2026-11-19): сотувчи сўраган «−N%» белгилари (`promoState.status == 'pending'`).
/// Ўқиш — тўғридан-тўғри Firestore (битта майдон тенглиги — автоматик индекс); ёзиш — ФАҚАТ `adminModeratePromo`
/// (транзакция + admin_audit + сотувчига хабар). Сервер тасдиқда нарх ўзгармаганини ва муддат ўтмаганини ҳам текширади.
class PromoModerationScreen extends StatefulWidget {
  const PromoModerationScreen({super.key, this.firestore, this.functions});

  final FirebaseFirestore? firestore;
  final FirebaseFunctions? functions;

  @override
  State<PromoModerationScreen> createState() => _PromoModerationScreenState();
}

class PromoModItem {
  const PromoModItem({required this.collection, required this.id, required this.title, required this.percent,
    required this.oldPrice, required this.price, this.until, this.photo = ''});
  final String collection;
  final String id;
  final String title;
  final int percent;
  final int oldPrice;
  final int price;
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
      oldPrice: i(s['oldPrice']),
      price: i(s['price']),
      until: s['until'] is Timestamp ? (s['until'] as Timestamp).toDate() : null,
      photo: photos is List && photos.isNotEmpty && photos.first is String ? photos.first as String : '',
    );
  }
}

class _PromoModerationScreenState extends State<PromoModerationScreen> {
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
      final res = await AdminCallable(widget.functions ?? FirebaseFunctions.instance).call('adminModeratePromo', {
        'collection': it.collection,
        'id': it.id,
        'decision': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      });
      if (!mounted) return;
      final status = '${res['status']}';
      final why = res['reason'] != null ? ' (${res['reason']})' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Натижа: $status$why')));
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Хато: ${e is AdminCallableException ? e.code : 'INTERNAL'}')));
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
        if (snap.hasError) return Center(child: TextButton(onPressed: () => setState(() => _future = _load()), child: const Text('Қайта юклаш')));
        final items = snap.data ?? const [];
        if (items.isEmpty) return const Center(child: Text('Кутилаётган чегирма йўқ'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            final busy = _busy.contains(it.id);
            final until = it.until == null ? '—' : '${it.until!.day.toString().padLeft(2, '0')}.${it.until!.month.toString().padLeft(2, '0')}.${it.until!.year}';
            return ListTile(
              key: ValueKey('promo_mod_${it.id}'),
              leading: it.photo.isEmpty ? const Icon(Icons.image_outlined) : Image.network(it.photo, width: 48, height: 48, fit: BoxFit.cover),
              title: Text('−${it.percent}%  ${it.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${it.collection == 'wholesale_products' ? 'Улгуржи' : 'Дўкон/бозор'} · эски ${formatPrice(it.oldPrice)} → ${formatPrice(it.price)} · $until гача'),
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
