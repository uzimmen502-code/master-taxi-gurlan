import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_widgets.dart';
import 'supermarket_home_screen.dart';

/// 3-экран: гуруҳ тафсилоти — нав чиплари → шу нав таклифлари нарх ўсиши бўйича.
///
/// [replaceProductId] берилса (саватдан «Ўзгартириш») — тугма таклифни алмаштиради ва қайтади.
class SmGroupScreen extends StatefulWidget {
  const SmGroupScreen({
    super.key,
    required this.controller,
    required this.group,
    this.replaceProductId,
  });

  final SupermarketController controller;
  final SmGroup group;
  final String? replaceProductId;

  @override
  State<SmGroupScreen> createState() => _SmGroupScreenState();
}

class _SmGroupScreenState extends State<SmGroupScreen> {
  String? _variety;

  @override
  void initState() {
    super.initState();
    final rp = widget.replaceProductId;
    if (rp != null) _variety = widget.controller.offers[rp]?.varietyId;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final lang = context.contentLang;
    return Scaffold(
      backgroundColor: context.ava.bg,
      appBar: AppBar(
        title: Text(widget.group.name(lang)),
        actions: [SmCartAction(controller: c, onTap: () => smOpenCart(context, c))],
      ),
      bottomNavigationBar: SmBottomBar(controller: c, onCart: () => smOpenCart(context, c)),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final all = c.offersByGroup[widget.group.id] ?? const <SmOffer>[];
          final varieties = smVarieties(all);
          final selected = varieties.any((v) => v.id == _variety) ? _variety : (varieties.isEmpty ? null : varieties.first.id);
          final offers = smSortOffersAsc(all.where((o) => o.varietyId == selected));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (varieties.length > 1 || (varieties.length == 1 && varieties.first.names.isNotEmpty))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in varieties)
                      ChoiceChip(
                        key: ValueKey('sm_variety_${v.id}'),
                        label: Text(v.names.isEmpty ? widget.group.name(lang) : localizedName(v.names, lang),
                            style: const TextStyle(fontSize: 15)),
                        selected: v.id == selected,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (_) => setState(() => _variety = v.id),
                      ),
                  ],
                ),
              if (widget.group.weighed || offers.any((o) => o.weighed)) ...[
                const SizedBox(height: 12),
                SmWeighedNote(percent: c.access.weighHoldPercent),
              ],
              const SizedBox(height: 12),
              for (final o in offers) ...[
                SmOfferCard(
                  key: ValueKey('sm_offer_${o.id}'),
                  offer: o,
                  groupName: widget.group.name(lang),
                  lang: lang,
                  replaceMode: widget.replaceProductId != null,
                  initialQtyMilli: widget.replaceProductId != null && o.id == widget.replaceProductId
                      ? c.cart.qtyOf(o.id)
                      : null,
                  onAdd: (qty) => _onAdd(o, qty, lang),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  void _onAdd(SmOffer o, int qtyMilli, String lang) {
    final c = widget.controller;
    final rp = widget.replaceProductId;
    if (rp != null) {
      c.replaceOffer(rp, o.id, qtyMilli);
      Navigator.of(context).pop();
      return;
    }
    c.addToCart(o.id, qtyMilli);
    final name = o.varietyNames.isNotEmpty ? o.varietyName(lang) : widget.group.name(lang);
    final unit = smUnitLabel(context, o.unit);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('sm_added_snack'),
        content: Text(context
            .tr('sm_added_to_cart')
            .replaceAll('{name}', name)
            .replaceAll('{qty}', '${smFormatQty(qtyMilli)} $unit'.trim())),
        action: SnackBarAction(label: context.tr('sm_tab_cart'), onPressed: () => smOpenCart(context, c)),
      ));
  }
}

/// Битта таклиф: сифат/қадоқ/партия ёрлиғи, нарх/бирлик, пакетда бирлик нархи, миқдор, сатр суммаси.
class SmOfferCard extends StatefulWidget {
  const SmOfferCard({
    super.key,
    required this.offer,
    required this.groupName,
    required this.lang,
    required this.onAdd,
    this.replaceMode = false,
    this.initialQtyMilli,
  });

  final SmOffer offer;
  final String groupName;
  final String lang;
  final ValueChanged<int> onAdd;
  final bool replaceMode;
  final int? initialQtyMilli;

  @override
  State<SmOfferCard> createState() => _SmOfferCardState();
}

class _SmOfferCardState extends State<SmOfferCard> {
  late int _qty = widget.initialQtyMilli != null && widget.initialQtyMilli! > 0
      ? smSnapQty(widget.initialQtyMilli!, widget.offer.stepMilli)
      : widget.offer.stepMilli;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = widget.offer;
    final enabled = o.available;
    final labels = [
      o.qualityName(widget.lang),
      o.packLabel,
    ].where((s) => s.isNotEmpty).join(' · ');
    final perUnit = o.unitPriceOfPack;
    final unitLabel = smUnitLabel(context, o.unit);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SmThumb(url: o.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.name.isEmpty ? widget.groupName : o.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                      if (labels.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(labels, style: TextStyle(fontSize: 14, color: c.ink2)),
                      ],
                      const SizedBox(height: 4),
                      Text(smPricePerUnit(context, o.price, o.unit),
                          key: ValueKey('sm_offer_price_${o.id}'),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                      if (perUnit != null)
                        Text(
                          context
                              .tr('sm_unit_price')
                              .replaceAll('{unit}', smUnitLabel(context, o.packUnit))
                              .replaceAll('{price}', formatMoney(perUnit)),
                          key: ValueKey('sm_offer_unit_price_${o.id}'),
                          style: TextStyle(fontSize: 14, color: c.ink2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!enabled)
              Text(context.tr('sm_out_of_stock'),
                  key: ValueKey('sm_offer_oos_${o.id}'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.danger))
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SmQtyStepper(
                    qtyMilli: _qty,
                    stepMilli: o.stepMilli,
                    unitLabel: unitLabel,
                    maxMilli: o.maxQtyMilli,
                    onChanged: (v) => setState(() => _qty = v),
                  ),
                  Text(formatMoney(smLineTotal(o.price, _qty)),
                      key: ValueKey('sm_offer_total_${o.id}'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                ],
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey('sm_offer_add_${o.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: enabled && smIsValidQty(_qty, o.stepMilli) ? () => widget.onAdd(_qty) : null,
                child: Text(
                  context.tr(widget.replaceMode ? 'sm_choose_this' : 'sm_add_to_cart'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
