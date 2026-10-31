import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/customer_confirm.dart';
import '../../../models/order_model.dart';
import '../../../services/customer_confirm_service.dart';
import 'customer_confirm_card.dart';

/// Мижознинг буюртма экранида: курьер «етказиб бўлмади» деди — мижоз тасдиқлайди ёки
/// «Олмоқчиман» дейди (эга, 2026-10-31; ҳамма мижоз учун). Ресторан (`restaurant`) ва
/// нон/бозор (`order`) буюртмаси — модул буюртма туридан.
///
/// Бош саҳифа банери `module_config/customer_confirm` ёқилмаган бўлса
/// кўринмайди; бу карточка буюртма ҳужжатидан (мижоз ўзи ўқийди) жонли
/// чиқади — қўшимча сўров йўқ. Қоида ва ҳолат — серверда
/// (`customerConfirmHandover`); бу ерда фақат кўрсатиш ва тугма.
class DeliveryFailedOrderCard extends StatelessWidget {
  const DeliveryFailedOrderCard({super.key, required this.order, this.service});

  final OrderModel order;
  final CustomerConfirmService? service;

  /// Буюртмадан тасдиқ элементи (сарлавҳа/изоҳ — маҳаллий матн калитлари).
  static CustomerConfirmation itemFor(OrderModel o) => CustomerConfirmation(
        module: o.isRestaurant ? CustomerConfirmModule.restaurant : CustomerConfirmModule.order,
        id: o.id,
        step: CustomerConfirmStep.deliveryFailed,
        canReject: true,
        failReason: o.deliveryFailedReason.isEmpty ? 'other' : o.deliveryFailedReason,
        leg: o.isRestaurant ? '' : 'delivery',
      );

  @override
  Widget build(BuildContext context) =>
      DeliveryFailedConfirmCard(item: itemFor(order), service: service);
}

/// Умумий «етказилмади» тасдиқ карточкаси (нон/бозор, ресторан, гилам, сут, йиғиш).
class DeliveryFailedConfirmCard extends StatefulWidget {
  const DeliveryFailedConfirmCard({super.key, required this.item, this.service});

  /// Модул/ид/сабаб/бўлак — ҳужжатдан (мижоз ўз ҳужжатини ўқийди).
  final CustomerConfirmation item;
  final CustomerConfirmService? service;

  /// Гилам/сут/йиғиш вазифаси учун элемент.
  static CustomerConfirmation taskItem({
    required String module,
    required String id,
    required String failReason,
    required String leg,
  }) =>
      CustomerConfirmation(
        module: module,
        id: id,
        step: CustomerConfirmStep.deliveryFailed,
        canReject: true,
        failReason: failReason.isEmpty ? 'other' : failReason,
        leg: leg,
      );

  @override
  State<DeliveryFailedConfirmCard> createState() => _DeliveryFailedConfirmCardState();
}

class _DeliveryFailedConfirmCardState extends State<DeliveryFailedConfirmCard> {
  late final CustomerConfirmService _service = widget.service ?? CustomerConfirmService();
  bool _busy = false;

  Future<void> _decide({required bool reject}) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? errKey;
    try {
      await _service.confirm(
        module: widget.item.module,
        id: widget.item.id,
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
    final doneKey = reject
        ? (widget.item.leg == 'pickup' ? 'customer_confirm_ready_to_give_done' : 'customer_confirm_rejected_done')
        : 'customer_confirm_done';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(context.tr(errKey ?? doneKey)),
      backgroundColor: errKey == null ? null : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CustomerConfirmCard(
      item: widget.item,
      busy: _busy,
      onConfirm: () => _decide(reject: false),
      onReject: () => _decide(reject: true),
    );
  }
}
