import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_widgets.dart';
import 'sm_checkout_screen.dart';
import 'sm_group_screen.dart';

/// 4-экран: ягона сават (битта сотувчи — AVA). Сақланиши — [SmCartStore] (илова қайта очилганда ҳам).
class SmCartScreen extends StatelessWidget {
  const SmCartScreen({super.key, required this.controller});

  final SupermarketController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('sm_cart_title'))),
      bottomNavigationBar: SmBottomBar(controller: controller, onCart: () {}, cartActive: true),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final cart = controller.cart;
          if (cart.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('sm_cart_empty'),
                    key: const ValueKey('sm_cart_empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
            );
          }
          final t = controller.totals;
          final hasWeighed = cart.lines.any((l) => controller.offers[l.productId]?.weighed == true);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (final l in cart.lines) ...[
                _CartLineTile(
                  controller: controller,
                  productId: l.productId,
                  qtyMilli: l.qtyMilli,
                  lang: lang,
                ),
                const SizedBox(height: 8),
              ],
              if (hasWeighed) ...[const SizedBox(height: 4), SmWeighedNote(percent: controller.access.weighHoldPercent), const SizedBox(height: 8)],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
                child: Column(
                  children: [
                    SmSumRow(
                        label: context.tr('sm_goods_total'),
                        amount: t.goodsTotal,
                        valueKey: const ValueKey('sm_cart_goods_total')),
                    if (controller.access.feePercent > 0)
                      SmSumRow(
                        label: context
                            .tr('sm_fee_estimate')
                            .replaceAll('{p}', '${controller.access.feePercent}'),
                        amount: t.feeEstimate,
                      ),
                    const SizedBox(height: 4),
                    Text(context.tr('sm_fee_final_note'), style: TextStyle(fontSize: 13, color: c.ink2)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('sm_checkout_btn'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: t.goodsTotal > 0 && t.unavailableIds.isEmpty
                    ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => SmCheckoutScreen(controller: controller),
                        ))
                    : null,
                child: Text(context.tr('sm_checkout'), style: const TextStyle(fontSize: 16)),
              ),
              if (t.unavailableIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(context.tr('sm_cart_remove_unavailable'),
                      key: const ValueKey('sm_cart_unavailable_note'), style: TextStyle(fontSize: 14, color: c.danger)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.controller, required this.productId, required this.qtyMilli, required this.lang});

  final SupermarketController controller;
  final String productId;
  final int qtyMilli;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final SmOffer? o = controller.offers[productId];
    final group = o == null ? null : controller.taxonomy.group(o.groupId);
    final ok = o != null && o.available;
    final title = o == null
        ? context.tr('sm_cart_item_missing')
        : (o.name.isNotEmpty ? o.name : (group?.name(lang) ?? productId));
    final sub = o == null ? '' : [o.qualityName(lang), o.packLabel].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      key: ValueKey('sm_cart_line_$productId'),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SmThumb(url: o?.imageUrl ?? '', size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 14, color: c.ink2)),
                    if (o != null)
                      Text(smPricePerUnit(context, o.price, o.unit), style: TextStyle(fontSize: 14, color: c.ink2)),
                    if (!ok)
                      Text(context.tr('sm_out_of_stock'),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.danger)),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('sm_cart_remove_$productId'),
                tooltip: context.tr('sm_remove'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => controller.removeLine(productId),
                icon: Icon(Icons.delete_outline_rounded, color: c.ink2),
              ),
            ],
          ),
          if (ok) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SmQtyStepper(
                  qtyMilli: qtyMilli,
                  stepMilli: o.stepMilli,
                  unitLabel: smUnitLabel(context, o.unit),
                  maxMilli: o.maxQtyMilli,
                  allowZero: true,
                  onChanged: (v) => controller.setQty(productId, v),
                ),
                Text(formatMoney(smLineTotal(o.price, qtyMilli)),
                    key: ValueKey('sm_cart_line_total_$productId'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                if (group != null)
                  TextButton(
                    key: ValueKey('sm_cart_edit_$productId'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => SmGroupScreen(controller: controller, group: group, replaceProductId: productId),
                    )),
                    child: Text(context.tr('sm_edit_offer'), style: const TextStyle(fontSize: 15)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
