import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_list.dart';
import '../domain/sm_qty.dart';
import '../supermarket_controller.dart';
import 'sm_widgets.dart';

/// Рўйхат / эски буюртмани ЖОРИЙ нархлар билан солиштириб, мижоз тасдиқласа — САВАТГА қўшади.
/// Ҳеч қачон буюртма бермайди ва пул ечмайди (эга 2026-11-21). Қўшилган қаторлар сони қайтади (0 — бекор).
Future<int> smCompareAndAddToCart(
  BuildContext context, {
  required SupermarketController controller,
  required List<SmListItem> items,
  Map<String, int> previousPrices = const {},
  required String origin,
}) async {
  final lines = smCompareItems(items,
      offers: controller.offers, offersByGroup: controller.offersByGroup, previousPrices: previousPrices);
  final selected = await showDialog<Set<int>>(
    context: context,
    builder: (_) => SmCompareDialog(controller: controller, lines: lines),
  );
  if (selected == null || selected.isEmpty) return 0;
  final cartLines = smCompareToCartLines(lines, selected: selected);
  controller.addLines(cartLines, origin: origin);
  return cartLines.length;
}

class SmCompareDialog extends StatefulWidget {
  const SmCompareDialog({super.key, required this.controller, required this.lines});

  final SupermarketController controller;
  final List<SmCompareLine> lines;

  @override
  State<SmCompareDialog> createState() => _SmCompareDialogState();
}

class _SmCompareDialogState extends State<SmCompareDialog> {
  late final Set<int> _sel = {
    for (var i = 0; i < widget.lines.length; i++)
      if (widget.lines[i].addable) i,
  };

  int get _total {
    var t = 0;
    for (final i in _sel) {
      final l = widget.lines[i];
      if (l.offer != null) t += smLineTotal(l.offer!.price, l.qtyMilli);
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    return AlertDialog(
      key: const ValueKey('sm_compare_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(context.tr('sm_compare_title')),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(context.tr('sm_compare_note'), key: const ValueKey('sm_compare_note'), style: TextStyle(fontSize: 14, color: c.ink2)),
            const SizedBox(height: 8),
            for (var i = 0; i < widget.lines.length; i++) _row(context, i, lang),
            const Divider(),
            SmSumRow(label: context.tr('sm_goods_total'), amount: _total, bold: true, valueKey: const ValueKey('sm_compare_total')),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('sm_cancel')),
        ),
        FilledButton(
          key: const ValueKey('sm_compare_confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _sel.isEmpty ? null : () => Navigator.of(context).pop(Set<int>.of(_sel)),
          child: Text(context.tr('sm_compare_add')),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i, String lang) {
    final c = context.ava;
    final l = widget.lines[i];
    final group = widget.controller.taxonomy.group(l.item.groupId);
    final o = l.offer;
    final title = o?.name.isNotEmpty == true ? o!.name : (group?.name(lang) ?? l.item.groupId);
    final unit = smUnitLabel(context, o?.unit ?? group?.unit ?? '');
    final notes = <(String, Color)>[
      switch (l.status) {
        SmCompareStatus.ok => ('', c.ink2),
        SmCompareStatus.priceChanged => (
            context
                .tr('sm_compare_price_changed')
                .replaceAll('{old}', formatMoney(l.previousPrice ?? 0))
                .replaceAll('{new}', formatMoney(o?.price ?? 0)),
            c.warn
          ),
        SmCompareStatus.differentPack => (
            context.tr('sm_compare_different').replaceAll(
                '{old}', l.previousOffer?.name.isNotEmpty == true ? l.previousOffer!.name : context.tr('sm_compare_old_offer')),
            c.warn
          ),
        SmCompareStatus.unavailable => (context.tr('sm_compare_unavailable'), c.danger),
      },
      if (l.qtyLimited) (context.tr('sm_compare_qty_limited'), c.warn),
    ].where((e) => e.$1.isNotEmpty).toList();
    final addable = l.addable;
    return CheckboxListTile(
      key: ValueKey('sm_compare_row_$i'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: addable && _sel.contains(i),
      onChanged: addable ? (v) => setState(() => v == true ? _sel.add(i) : _sel.remove(i)) : null,
      title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: addable ? c.ink : c.ink3)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o != null)
            Text(
              '${smFormatQty(l.qtyMilli)} $unit × ${smPricePerUnit(context, o.price, o.unit)} = ${formatMoney(smLineTotal(o.price, l.qtyMilli))}',
              style: TextStyle(fontSize: 14, color: c.ink2),
            ),
          for (final (j, n) in notes.indexed)
            Text(n.$1, key: ValueKey('sm_compare_note_${i}_$j'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: n.$2)),
        ],
      ),
    );
  }
}
