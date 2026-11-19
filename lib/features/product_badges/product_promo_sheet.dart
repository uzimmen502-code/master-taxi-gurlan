import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import 'product_badge.dart';

/// Сотувчи: «Акция» бўлими (эга 2026-11-19). Фақат `promoRequest` ёзилади (Rules: шакл, ≤ 30 кун,
/// requestedAt == request.time). Фоиз, 7 кун қоидаси ва модерация — серверда (functions/product_promo.js);
/// натижа (`promoState`) шу ерда жонли кўринади.
const int kPromoMaxDays = 30;

/// Жорий нарх: tv_shop_items — `price`; wholesale_products — энг кичик minQty поғонаси (сервер `priceOf` билан бир хил).
int? promoPriceOf(String collection, Map<String, dynamic> d) {
  if (collection == 'wholesale_products') {
    final tiers = d['priceTiers'];
    if (tiers is! List) return null;
    Map? best;
    for (final t in tiers) {
      if (t is! Map) continue;
      final q = t['minQty'];
      final p = t['price'];
      if (q is! int || q < 1 || p is! int || p <= 0) continue;
      if (best == null || q < (best['minQty'] as int)) best = t;
    }
    return best == null ? null : best['price'] as int;
  }
  final p = d['price'];
  return p is int && p >= 0 ? p : null;
}

/// Фоиз чегараси — сервер PERCENT_MIN/MAX ва Rules билан бир хил (1..50, эга 2026-11-20).
const int kPromoPercentMin = 1;
const int kPromoPercentMax = 50;

/// Мижоздаги олдиндан текширув (сервер барибир текширади, жумладан 7 кун қоидасини): калит ёки null.
String? promoClientError({required String kind, required int? price, required int? percent}) {
  if (kind != 'discount') return null;
  if (price == null || price <= 0) return 'promo_reason_PRICE_REQUIRED';
  if (percent == null || percent < kPromoPercentMin || percent > kPromoPercentMax) return 'promo_reason_PERCENT_INVALID';
  if (promoDiscountedPrice(price, percent) >= price) return 'promo_reason_DISCOUNT_TOO_SMALL';
  return null;
}

/// Чегирмали нарх: floor(price × (100 − pct) / 100), камида 1 — серверники билан бир хил (кўрсатиш учун).
int promoDiscountedPrice(int price, int pct) {
  if (price <= 0) return price;
  final v = (price * (100 - pct)) ~/ 100;
  return v < 1 ? 1 : v;
}

/// Танланган кун охири, лекин ҳозирдан ≤ 30 кун (5 дақиқа захира — сервер вақти фарқи).
DateTime promoUntilFor(DateTime day, DateTime now) {
  final end = DateTime(day.year, day.month, day.day, 23, 59);
  final cap = now.add(const Duration(days: kPromoMaxDays)).subtract(const Duration(minutes: 5));
  return end.isAfter(cap) ? cap : end;
}

/// Форма ичидаги ихчам қатор: «Акция» — ҳолат + очиш.
class ProductPromoTile extends StatelessWidget {
  const ProductPromoTile({super.key, required this.collection, required this.docId});

  final String collection;
  final String docId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        key: const ValueKey('product_promo_tile'),
        leading: const Icon(Icons.local_offer_outlined, color: Color(0xFFE53935)),
        title: Text(context.tr('promo_section_title')),
        subtitle: Text(context.tr('promo_section_hint')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProductPromoSheet(collection: collection, docId: docId),
        ),
      ),
    );
  }
}

class ProductPromoSheet extends StatefulWidget {
  const ProductPromoSheet({super.key, required this.collection, required this.docId, this.firestore});

  final String collection;
  final String docId;
  final FirebaseFirestore? firestore;

  @override
  State<ProductPromoSheet> createState() => _ProductPromoSheetState();
}

class _ProductPromoSheetState extends State<ProductPromoSheet> {
  late final FirebaseFirestore _db = widget.firestore ?? FirebaseFirestore.instance;
  late final DocumentReference<Map<String, dynamic>> _ref = _db.collection(widget.collection).doc(widget.docId);
  final _percent = TextEditingController();
  String _kind = 'discount';
  DateTime _day = DateTime.now().add(const Duration(days: 7));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  Future<void> _submit(int? price) async {
    final pct = int.tryParse(_percent.text.replaceAll(RegExp(r'\D'), ''));
    final err = promoClientError(kind: _kind, price: price, percent: pct);
    if (err != null) return setState(() => _error = err);
    setState(() { _busy = true; _error = null; });
    try {
      await _ref.update({
        'promoRequest': {
          'kind': _kind,
          if (_kind == 'discount') 'percent': pct,
          'until': Timestamp.fromDate(promoUntilFor(_day, DateTime.now())),
          'requestedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('[promo] submit failed: $e');
      if (mounted) setState(() => _error = 'promo_submit_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _ref.update({'promoRequest': FieldValue.delete()});
    } catch (e) {
      debugPrint('[promo] cancel failed: $e');
      if (mounted) setState(() => _error = 'promo_submit_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now,
      lastDate: now.add(const Duration(days: kPromoMaxDays - 1)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? const <String, dynamic>{};
        final badge = ProductBadgeData.fromMap(d);
        final price = promoPriceOf(widget.collection, d);
        final pct = int.tryParse(_percent.text.replaceAll(RegExp(r'\D'), ''));
        final preview = (_kind == 'discount' && pct != null && pct >= kPromoPercentMin && pct <= kPromoPercentMax && price != null && price > 0)
            ? promoDiscountedPrice(price, pct)
            : null;
        final active = badge.activeDiscount(DateTime.now());
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('promo_section_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _StatusLine(badge: badge),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'discount', label: Text(context.tr('promo_kind_discount'))),
                    ButtonSegment(value: 'promo', label: Text(context.tr('product_badge_promo'))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _busy ? null : (s) => setState(() { _kind = s.first; _error = null; }),
                ),
                const SizedBox(height: 12),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      context.tr('promo_active_line')
                          .replaceAll('{base}', formatPrice(badge.basePrice))
                          .replaceAll('{price}', price == null ? '—' : formatPrice(price))
                          .replaceAll('{percent}', '${badge.percent}'),
                      key: const ValueKey('promo_active_line'),
                    ),
                  ),
                if (_kind == 'discount' && !active) ...[
                  Text('${context.tr('promo_current_price')}: ${price == null ? '—' : formatPrice(price)}'),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('promo_percent'),
                    controller: _percent,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: context.tr('promo_percent'),
                      helperText: context.tr('promo_percent_rule'),
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      suffixText: '%',
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      context.tr('promo_new_price').replaceAll('{price}', formatPrice(preview)),
                      key: const ValueKey('promo_new_price'),
                      style: const TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  key: const ValueKey('promo_until'),
                  onPressed: _busy ? null : _pickDay,
                  icon: const Icon(Icons.event),
                  label: Text('${context.tr('promo_until')}: ${_day.day.toString().padLeft(2, '0')}.${_day.month.toString().padLeft(2, '0')}.${_day.year}'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(context.tr(_error!), key: const ValueKey('promo_error'), style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('promo_submit'),
                  onPressed: _busy || (active && _kind == 'discount') ? null : () => _submit(price),
                  child: Text(context.tr(_kind == 'discount' ? 'promo_submit_review' : 'promo_submit')),
                ),
                if (badge.hasRequest)
                  TextButton(
                    key: const ValueKey('promo_cancel'),
                    onPressed: _busy ? null : _cancel,
                    child: Text(context.tr('promo_cancel')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.badge});
  final ProductBadgeData badge;

  @override
  Widget build(BuildContext context) {
    final s = badge.stateStatus;
    if (s.isEmpty) return const SizedBox.shrink();
    String text;
    Color color;
    switch (s) {
      case 'pending':
        text = context.tr('promo_state_pending').replaceAll('{percent}', '${badge.statePercent}');
        color = Colors.orange.shade800;
      case 'active':
        text = context.tr('promo_state_active');
        color = Colors.green.shade700;
      case 'rejected':
        final reason = context.tr('promo_reason_${badge.stateReason}');
        text = badge.stateNote.isNotEmpty ? '$reason: ${badge.stateNote}' : reason;
        color = Colors.red.shade700;
      default:
        text = context.tr('promo_reason_${badge.stateReason}');
        color = Colors.grey.shade700;
    }
    return Text(text, key: ValueKey('promo_state_$s'), style: TextStyle(color: color, fontWeight: FontWeight.w600));
  }
}
