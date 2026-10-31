import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/customer_confirm.dart';
import '../../../models/order_model.dart';
import '../../../services/customer_confirm_service.dart';
import 'customer_confirm_card.dart';

/// Мижознинг ресторан буюртмаси экранида: курьер «етказиб бўлмади» деди —
/// мижоз тасдиқлайди ёки «Олмоқчиман» дейди (эга, 2026-10-31; ҳамма мижоз учун).
///
/// Бош саҳифа банери `module_config/customer_confirm` ёқилмаган бўлса
/// кўринмайди; бу карточка буюртма ҳужжатидан (мижоз ўзи ўқийди) жонли
/// чиқади — қўшимча сўров йўқ. Қоида ва ҳолат — серверда
/// (`customerConfirmHandover`); бу ерда фақат кўрсатиш ва тугма.
class DeliveryFailedOrderCard extends StatefulWidget {
  const DeliveryFailedOrderCard({super.key, required this.order, this.service});

  final OrderModel order;
  final CustomerConfirmService? service;

  /// Буюртмадан тасдиқ элементи (сарлавҳа/изоҳ — маҳаллий матн калитлари).
  static CustomerConfirmation itemFor(OrderModel o) => CustomerConfirmation(
        module: CustomerConfirmModule.restaurant,
        id: o.id,
        step: CustomerConfirmStep.deliveryFailed,
        canReject: true,
        failReason: o.deliveryFailedReason.isEmpty ? 'other' : o.deliveryFailedReason,
      );

  @override
  State<DeliveryFailedOrderCard> createState() => _DeliveryFailedOrderCardState();
}

class _DeliveryFailedOrderCardState extends State<DeliveryFailedOrderCard> {
  late final CustomerConfirmService _service = widget.service ?? CustomerConfirmService();
  bool _busy = false;

  Future<void> _decide({required bool reject}) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? errKey;
    try {
      await _service.confirm(
        module: CustomerConfirmModule.restaurant,
        id: widget.order.id,
        step: CustomerConfirmStep.deliveryFailed,
        reject: reject,
      );
    } on CustomerConfirmException catch (e) {
      errKey = customerConfirmErrorKey(e.reason);
    } catch (_) {
      errKey = customerConfirmErrorKey('');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(context.tr(errKey ?? (reject ? 'customer_confirm_rejected_done' : 'customer_confirm_done'))),
      backgroundColor: errKey == null ? null : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CustomerConfirmCard(
      item: DeliveryFailedOrderCard.itemFor(widget.order),
      busy: _busy,
      onConfirm: () => _decide(reject: false),
      onReject: () => _decide(reject: true),
    );
  }
}
