import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';

/// «<Сотувчи> · Сотувчининг бошқа маҳсулотлари →» — барча бозорлардаги тафсилот экранлари учун ЯГОНА қатор
/// (эга, 2026-11-16). Аввалги «Сотувчининг барча маҳсулотлари» карточка/тугмалари ўрнига.
///
/// Кўринади фақат сотувчида шу манбада 1 тадан КЎП фаол маҳсулот/эълон бўлса. Текширув — [countActive]
/// (битта арзон `count()` агрегат сўрови), натижа сеанс давомида [cacheKey] бўйича хотирада (бир сотувчи учун
/// қайта ўқилмайди; бир вақтдаги сўровлар битта Future'га бирлашади). Номаълум/хато — қатор йўқ
/// ([fallback] бўлса — у кўрсатилади).
class SellerOtherProductsRow extends StatefulWidget {
  const SellerOtherProductsRow({
    super.key,
    required this.cacheKey,
    required this.sellerName,
    required this.countActive,
    required this.onOpen,
    this.fallback,
    this.color,
  });

  /// Манба + сотувчи, мас. `ads:998901112233`, `tv:998…`, `tv_biz:<businessId>`, `wholesale:998…`.
  final String cacheKey;
  final String sellerName;

  /// Сотувчининг шу манбадаги фаол ёзувлари сони.
  final Future<int> Function() countActive;
  final VoidCallback onOpen;

  /// Қатор кўринмаганда (номаълум / ≤ 1 / хато) ўрнига (мас. оддий сотувчи номи).
  final Widget? fallback;

  /// Матн ва стрелка ранги (қоронғи экранлар учун); сукут — мавзу `primary`.
  final Color? color;

  static final Map<String, bool> _cache = <String, bool>{};
  static final Map<String, Future<bool>> _inflight = <String, Future<bool>>{};

  /// Сеанс хотирасидаги натижа (тест/диагностика): `null` — ҳали номаълум.
  static bool? cached(String cacheKey) => _cache[cacheKey];

  @visibleForTesting
  static void debugSeed(String cacheKey, bool moreThanOne) => _cache[cacheKey] = moreThanOne;

  @visibleForTesting
  static void debugReset() {
    _cache.clear();
    _inflight.clear();
  }

  /// 1 тадан кўп бўлса `true`. Хато — `null` (хотирага ёзилмайди, кейинги очилишда қайта уринади).
  static Future<bool?> resolve(String cacheKey, Future<int> Function() countActive) async {
    final hit = _cache[cacheKey];
    if (hit != null) return hit;
    final future = _inflight[cacheKey] ??= () async {
      final n = await countActive();
      return n > 1;
    }();
    try {
      final v = await future;
      _cache[cacheKey] = v;
      return v;
    } catch (e) {
      // Фойдаланувчига хато кўрсатилмайди — қатор шунчаки чиқмайди (25-банд).
      debugPrint('[SellerOtherProducts] SELLER_OTHER_COUNT_FAILED key=$cacheKey: $e');
      return null;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  @override
  State<SellerOtherProductsRow> createState() => _SellerOtherProductsRowState();
}

class _SellerOtherProductsRowState extends State<SellerOtherProductsRow> {
  bool? _more;

  @override
  void initState() {
    super.initState();
    _more = SellerOtherProductsRow._cache[widget.cacheKey];
    if (_more == null) _load();
  }

  @override
  void didUpdateWidget(covariant SellerOtherProductsRow old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) {
      _more = SellerOtherProductsRow._cache[widget.cacheKey];
      if (_more == null) _load();
    }
  }

  Future<void> _load() async {
    final key = widget.cacheKey;
    final v = await SellerOtherProductsRow.resolve(key, widget.countActive);
    if (!mounted || key != widget.cacheKey) return;
    setState(() => _more = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_more != true) return widget.fallback ?? const SizedBox.shrink();
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final name = widget.sellerName.trim();
    final label = context.tr('seller_other_products');
    final text = name.isEmpty ? label : '$name · $label';
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('seller_other_products_row'),
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  key: const ValueKey('seller_other_products_text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: color),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
