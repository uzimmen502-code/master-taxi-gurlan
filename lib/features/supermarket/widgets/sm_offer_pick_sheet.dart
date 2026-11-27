import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import 'sm_widgets.dart';

/// Ихчам танлов ойнаси (Тезкор харид / Ҳафталик сават): нав → таклифлар нарх ўсиши бўйича → миқдор →
/// «Қўшиш». Натижа — `(offer, qtyMilli)`; нима қилиш — чақирувчида (сават ёки рўйхат).
Future<({SmOffer offer, int qtyMilli})?> showSmOfferPickSheet(
  BuildContext context, {
  required SupermarketController controller,
  required SmGroup group,
  String? initialOfferId,
  int? initialQtyMilli,
}) =>
    showModalBottomSheet<({SmOffer offer, int qtyMilli})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SmOfferPickSheet(
        controller: controller,
        group: group,
        initialOfferId: initialOfferId,
        initialQtyMilli: initialQtyMilli,
      ),
    );

class SmOfferPickSheet extends StatefulWidget {
  const SmOfferPickSheet({
    super.key,
    required this.controller,
    required this.group,
    this.initialOfferId,
    this.initialQtyMilli,
  });

  final SupermarketController controller;
  final SmGroup group;
  final String? initialOfferId;
  final int? initialQtyMilli;

  @override
  State<SmOfferPickSheet> createState() => _SmOfferPickSheetState();
}

class _SmOfferPickSheetState extends State<SmOfferPickSheet> {
  String? _variety;
  String? _offerId;
  int _qty = 0;

  List<SmOffer> get _all => widget.controller.offersByGroup[widget.group.id] ?? const <SmOffer>[];

  @override
  void initState() {
    super.initState();
    final init = widget.controller.offers[widget.initialOfferId ?? ''];
    if (init != null && init.available) {
      _variety = init.varietyId;
      _offerId = init.id;
      _qty = smSnapQty(widget.initialQtyMilli ?? init.stepMilli, init.stepMilli);
    }
  }

  SmOffer? get _selected {
    final o = widget.controller.offers[_offerId ?? ''];
    return o != null && o.available ? o : null;
  }

  void _select(SmOffer o) => setState(() {
        _offerId = o.id;
        _qty = _qty <= 0 ? o.stepMilli : smSnapQty(_qty, o.stepMilli);
        final max = o.maxQtyMilli;
        if (max != null && _qty > max) _qty = (max ~/ o.stepMilli) * o.stepMilli;
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final varieties = smVarieties(_all);
    final variety = varieties.any((v) => v.id == _variety) ? _variety : (varieties.isEmpty ? null : varieties.first.id);
    final list = smSortOffersAsc(_all.where((o) => o.varietyId == variety));
    final sel = _selected;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        key: const ValueKey('sm_pick_sheet'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(widget.group.name(lang), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          if (varieties.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in varieties)
                  ChoiceChip(
                    key: ValueKey('sm_pick_variety_${v.id}'),
                    label: Text(v.names.isEmpty ? widget.group.name(lang) : localizedName(v.names, lang),
                        style: const TextStyle(fontSize: 15)),
                    selected: v.id == variety,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => setState(() => _variety = v.id),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          for (final o in list)
            _OfferOption(
              offer: o,
              lang: lang,
              selected: o.id == sel?.id,
              onTap: o.available ? () => _select(o) : null,
            ),
          const SizedBox(height: 12),
          if (sel != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SmQtyStepper(
                  qtyMilli: _qty,
                  stepMilli: sel.stepMilli,
                  unitLabel: smUnitLabel(context, sel.unit),
                  maxMilli: sel.maxQtyMilli,
                  onChanged: (v) => setState(() => _qty = v),
                ),
                Text(formatMoney(smLineTotal(sel.price, _qty)),
                    key: const ValueKey('sm_pick_total'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
              ],
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('sm_pick_add'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: sel != null && smIsValidQty(_qty, sel.stepMilli)
                ? () => Navigator.of(context).pop((offer: sel, qtyMilli: _qty))
                : null,
            child: Text(context.tr('sm_pick_add'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _OfferOption extends StatelessWidget {
  const _OfferOption({required this.offer, required this.lang, required this.selected, this.onTap});

  final SmOffer offer;
  final String lang;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = offer;
    final label = [o.qualityName(lang), o.packLabel].where((s) => s.isNotEmpty).join(' · ');
    final perUnit = o.unitPriceOfPack;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        key: ValueKey('sm_pick_offer_${o.id}'),
        color: selected ? c.brandSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? c.brand : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: onTap == null ? c.ink3 : (selected ? c.brandText : c.ink2)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.ink)),
                        if (label.isNotEmpty) Text(label, style: TextStyle(fontSize: 13, color: c.ink2)),
                        if (onTap == null)
                          Text(context.tr(smUnavailableKey(o)), style: TextStyle(fontSize: 13, color: c.danger))
                        else if (perUnit != null)
                          Text(
                            context
                                .tr('sm_unit_price')
                                .replaceAll('{unit}', smUnitLabel(context, o.packUnit))
                                .replaceAll('{price}', formatMoney(perUnit)),
                            style: TextStyle(fontSize: 13, color: c.ink2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(smPricePerUnit(context, o.price, o.unit),
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
