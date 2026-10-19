// Таом формаси — «Миқдорга чегирма» блоки (D-REST-25).
//
// ИХТИЁРИЙ, йиғиладиган карточка (форма узун кўринмайди): ресторан таомига 3 тагача поғона қўяди
// («10 та ва ундан кўп — ҳар бири 32 000»). Чегирмани ресторан ЎЗ ҳисобидан беради, AVA бермайди —
// шуни матн аниқ айтади. Қоида ва текширув соф ([QtyTiers]) ва серверда ҳам такрорланади; бу ерда фақат
// киритиш ва кўрсатиш. Ўзгарганда [onChanged] чақирилади: тўлиқ қаторлардан [QtyTier] рўйхати ва
// «ярим тўлдирилган қатор бор» белгиси (форма сақлашни шунга кўра тўхтатади).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/qty_tiers.dart';

/// Форма ҳолати: [tiers] — тўлиқ қаторлар; [hasIncompleteRow] — битта майдони тўлган, иккинчиси бўш қатор бор.
class QtyTiersDraft {
  const QtyTiersDraft(this.tiers, {this.hasIncompleteRow = false});

  final List<QtyTier> tiers;
  final bool hasIncompleteRow;

  /// Хато калитлари ([QtyTiersError]); бўш рўйхат — сақлаш мумкин.
  List<String> errorsFor(int basePrice) => [
        if (hasIncompleteRow) QtyTiersError.incomplete,
        ...QtyTiers.validate(basePrice, tiers),
      ];
}

class QtyTiersEditor extends StatefulWidget {
  const QtyTiersEditor({
    super.key,
    required this.initial,
    required this.priceController,
    required this.onChanged,
    this.showErrors = false,
  });

  final List<QtyTier> initial;

  /// Таом (асосий) нархи майдони: поғона нархи шундан кам бўлиши шарт.
  final TextEditingController priceController;
  final ValueChanged<QtyTiersDraft> onChanged;

  /// Сақлаш уриниб кўрилгандан кейин `true`: карточка очилади ва хато кўрсатилади.
  final bool showErrors;

  @override
  State<QtyTiersEditor> createState() => _QtyTiersEditorState();
}

class _Row {
  _Row({String qty = '', String price = ''})
      : qty = TextEditingController(text: qty),
        price = TextEditingController(text: price);

  final TextEditingController qty;
  final TextEditingController price;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class _QtyTiersEditorState extends State<QtyTiersEditor> {
  late final List<_Row> _rows = [for (final t in widget.initial) _Row(qty: '${t.minQty}', price: '${t.price}')];
  late bool _open = widget.initial.isNotEmpty;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    widget.priceController.addListener(_onBasePrice);
  }

  @override
  void didUpdateWidget(QtyTiersEditor old) {
    super.didUpdateWidget(old);
    if (widget.showErrors && !old.showErrors && !_open) setState(() => _open = true);
  }

  @override
  void dispose() {
    widget.priceController.removeListener(_onBasePrice);
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _onBasePrice() {
    if (mounted) setState(() {}); // асосий нарх ўзгарди — хато ҳолати қайта ҳисобланади
  }

  int get _base => int.tryParse(widget.priceController.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  static int? _n(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  QtyTiersDraft get _draft {
    final tiers = <QtyTier>[];
    var incomplete = false;
    for (final r in _rows) {
      final q = _n(r.qty);
      final p = _n(r.price);
      if (q == null && p == null) {
        // Бутунлай бўш қатор — эътиборсиз (ҳали тўлдирилмаган).
        if (r.qty.text.trim().isNotEmpty || r.price.text.trim().isNotEmpty) incomplete = true;
        continue;
      }
      if (q == null || p == null) {
        incomplete = true;
        continue;
      }
      tiers.add(QtyTier(minQty: q, price: p));
    }
    return QtyTiersDraft(tiers, hasIncompleteRow: incomplete);
  }

  void _changed() {
    setState(() => _touched = true);
    widget.onChanged(_draft);
  }

  void _add() {
    if (_rows.length >= QtyTiers.maxTiers) return;
    setState(() => _rows.add(_Row()));
  }

  void _remove(int i) {
    final r = _rows.removeAt(i);
    r.dispose();
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final draft = _draft;
    final errs = draft.errorsFor(_base);
    final showErr = errs.isNotEmpty && (_touched || widget.showErrors);
    final count = draft.tiers.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        key: const ValueKey('qty-tiers-card'),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AvaRadius.card),
          border: Border.all(color: showErr ? c.danger : c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('qty-tiers-header'),
              borderRadius: BorderRadius.circular(AvaRadius.card),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.local_offer_outlined, size: 18, color: count > 0 ? c.ok : c.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('restaurants_m_tiers_title'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                    ),
                    if (count > 0)
                      Text('$count', key: const ValueKey('qty-tiers-count'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ok)),
                    const SizedBox(width: 4),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.ink3),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr('restaurants_m_tiers_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _rows.length; i++) _rowView(context, i),
                    if (showErr)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          errs.map((e) => context.tr('restaurants_m_tiers_err_$e')).join(' '),
                          key: const ValueKey('qty-tiers-error'),
                          style: TextStyle(fontSize: 12, color: c.danger),
                        ),
                      ),
                    if (_rows.length < QtyTiers.maxTiers)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('qty-tiers-add'),
                          onPressed: _add,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(context.tr('restaurants_m_tiers_add')),
                        ),
                      ),
                    if (_rows.isNotEmpty && _base > 0 && count > 0 && errs.isEmpty) _preview(context),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowView(BuildContext context, int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('qty-tier-min-$i'),
              controller: r.qty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: context.tr('restaurants_m_tiers_from'),
                suffixText: context.tr('restaurants_m_tiers_pcs'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              key: ValueKey('qty-tier-price-$i'),
              controller: r.price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              onChanged: (_) => _changed(),
              decoration: InputDecoration(
                labelText: context.tr('restaurants_m_tiers_price'),
                suffixText: context.tr('sum'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            key: ValueKey('qty-tier-remove-$i'),
            tooltip: context.tr('delete'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _remove(i),
          ),
        ],
      ),
    );
  }

  /// Мисол: 12 та буюртмада нарх қанча бўлиши — ресторан нима бераётганини кўради.
  Widget _preview(BuildContext context) {
    final c = context.ava;
    final tiers = _draft.tiers;
    final sample = tiers.last.minQty;
    final unit = QtyTiers.unitPriceFor(_base, tiers, sample).unitPrice;
    final text = context
        .tr('restaurants_m_tiers_preview')
        .replaceAll('{n}', '$sample')
        .replaceAll('{total}', formatPrice(unit * sample))
        .replaceAll('{saved}', formatPrice((_base - unit) * sample));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, key: const ValueKey('qty-tiers-preview'), style: TextStyle(fontSize: 12, color: c.ok)),
    );
  }
}
