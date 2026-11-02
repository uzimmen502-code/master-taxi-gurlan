// «Буюртмалар» ҳабидаги «Менинг бизнесим» буюртмаси карточкаси (харидор): дўкон номи, ҳолат, жами, сана ва
// (сотувчи қабул қилгунча) «Бекор қилиш». Тафсилот — [BusinessOrderScreen].

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import 'business_order_widgets.dart';

class BusinessOrderHubTile extends StatelessWidget {
  const BusinessOrderHubTile({super.key, required this.order, this.onCancel, this.cancelling = false});

  final OrderModel order;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    return Container(
      key: ValueKey('biz_hub_tile_${o.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_rounded, size: 18, color: c.brandText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  o.businessName.isEmpty ? context.tr('biz_order_module') : o.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: c.ink),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: BusinessOrderStatusPill(status: o.businessStatus)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  o.createdAt == null ? '' : bizOrderDateLabel(o.createdAt!),
                  style: TextStyle(color: c.ink2, fontSize: 12),
                ),
              ),
              Text(formatMoney(o.total), style: TextStyle(fontWeight: FontWeight.w800, color: c.ink)),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('biz_hub_cancel_${o.id}'),
                onPressed: cancelling ? null : onCancel,
                style: TextButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(0, AvaTap.minSize)),
                child: cancelling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('biz_order_cancel')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
