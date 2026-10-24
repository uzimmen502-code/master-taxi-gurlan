import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/carpet_wash_order.dart';
import '../../../models/customer_confirm.dart';
import '../../../services/carpet_wash_service.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../courier/widgets/courier_task_list.dart';
import '../../customer_confirm/widgets/courier_awaiting_notice.dart';
import '../../../core/utils/user_error.dart';

const _brown = Color(0xFF6D4C41);

/// Kuryer — gilam olib ketish / qaytarish vazifalari.
///
/// Рўйхатлар — `courierListCarpetTasks` callable. Аввал
/// `carpet_wash_orders` оқимлари эди: `courier` `isStaff()`дан чиқарилгач
/// (D-SERVICE-4 / D-CLEAN-1) қоида уларни capability курьерга рад этарди,
/// очиш эса ҳар бир курьерга вазифани олмасданоқ мижоз исми, телефони ва
/// манзилини берарди (40-қоида).
class CarpetWashCourierScreen extends StatefulWidget {
  const CarpetWashCourierScreen({super.key, this.service});

  final CarpetWashService? service;

  @override
  State<CarpetWashCourierScreen> createState() =>
      _CarpetWashCourierScreenState();
}

class _CarpetWashCourierScreenState extends State<CarpetWashCourierScreen> {
  late final CarpetWashService _service =
      widget.service ?? CarpetWashService();
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _phone = phone);
  }

  /// Амал, кейин рўйхатни янгилаш (рад бўлса ҳам — вазифа ўзгарган бўлиши мумкин).
  Future<void> _act(
    Future<void> Function() action,
    Future<void> Function() reload,
  ) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userErrorMessage(context, e))),
        );
      }
    }
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_phone.length < 9) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AvaLight.surface2,
        appBar: AppBar(
          title: Text(context.tr('carpet_courier_title')),
          backgroundColor: _brown,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: context.tr('carpet_pickup_tab')),
              Tab(text: context.tr('carpet_return_tab')),
              Tab(text: context.tr('carpet_active_tab')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ClaimableTab(
              load: () =>
                  _service.listCourierTasks(CarpetWashService.courierListPickup),
              emptyText: context.tr('carpet_no_pickup_tasks'),
              actionLabel: context.tr('carpet_claim_pickup'),
              onAction: (order, reload) => _act(
                () => _service.courierClaimPickup(
                  courierPhone: _phone,
                  orderId: order.id,
                ),
                reload,
              ),
            ),
            _ClaimableTab(
              load: () =>
                  _service.listCourierTasks(CarpetWashService.courierListReturn),
              emptyText: context.tr('carpet_no_return_tasks'),
              actionLabel: context.tr('carpet_claim_return'),
              onAction: (order, reload) => _act(
                () => _service.courierClaimReturn(
                  courierPhone: _phone,
                  orderId: order.id,
                ),
                reload,
              ),
            ),
            _ActiveCourierTab(
              load: _loadActive,
              awaiting: _awaiting,
              onNext: _advance,
              onCall: callPhone,
            ),
          ],
        ),
      ),
    );
  }

  /// Мижоз тасдиғи кутилаётган вазифалар: `id → ўша пайтдаги status` (D2/D7).
  /// Сервер `awaitingCustomer: true` қайтарганда тўлади; рўйхатда вазифа
  /// ўзгарса (мижоз тасдиқлади) ёки йўқолса — [_loadActive] тозалайди.
  /// Илова қайта очилса бўш бўлади: тугма қайта босилса сервер (идемпотент)
  /// яна `awaitingCustomer` қайтаради.
  final Map<String, String> _awaiting = {};

  Future<List<CarpetWashOrder>> _loadActive() async {
    final list =
        await _service.listCourierTasks(CarpetWashService.courierListActive);
    if (_awaiting.isNotEmpty) {
      final stale = [
        for (final e in _awaiting.entries)
          if (!list.any((o) => o.id == e.key && o.status == e.value)) e.key,
      ];
      if (stale.isNotEmpty && mounted) {
        setState(() => stale.forEach(_awaiting.remove));
      }
    }
    return list;
  }

  /// «Фаол» вазифанинг навбатдаги қадами, кейин рўйхатни янгилаш.
  Future<void> _advance(
    CarpetWashOrder order,
    Future<void> Function() reload,
  ) async {
    try {
      final r = await _nextStep(order);
      if (r.awaitingCustomer && mounted) {
        setState(() => _awaiting[order.id] = order.status);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
    await reload();
  }

  /// Фаол вазифанинг навбатдаги қадами: аввал «етиб келдим», кейин
  /// «олиб кетилди» / «етказилди».
  Future<CourierActionResult> _nextStep(CarpetWashOrder order) async {
    final isPickup = order.status == CarpetWashOrder.statusPickupInDelivery;
    final hasArrived =
        isPickup ? order.pickupArrivedAt != null : order.returnArrivedAt != null;
    if (!hasArrived) {
      await _service.courierMarkArrived(
        courierPhone: _phone,
        orderId: order.id,
        leg: isPickup ? 'pickup' : 'return',
      );
      return CourierActionResult.completed;
    }
    return isPickup
        ? _service.courierMarkPickedUp(courierPhone: _phone, orderId: order.id)
        : _service.courierMarkDelivered(courierPhone: _phone, orderId: order.id);
  }
}

typedef _TaskAction = Future<void> Function(
  CarpetWashOrder order,
  Future<void> Function() reload,
);

/// Олиш учун вазифалар: фақат гилам сони — мижоз маълумоти вазифани
/// олгандан кейин «Фаол» табида.
class _ClaimableTab extends StatelessWidget {
  const _ClaimableTab({
    required this.load,
    required this.emptyText,
    required this.actionLabel,
    required this.onAction,
  });

  final Future<List<CarpetWashOrder>> Function() load;
  final String emptyText;
  final String actionLabel;
  final _TaskAction onAction;

  @override
  Widget build(BuildContext context) {
    return CourierTaskList<CarpetWashOrder>(
      load: load,
      emptyText: emptyText,
      itemBuilder: (context, order, reload) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${order.carpetCount} ${context.tr('carpet_count_suffix')}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('courier_task_details_after_claim'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => onAction(order, reload),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brown,
                  foregroundColor: Colors.white,
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шу курьер олган вазифалар — сервер фақат уникини қайтаради.
class _ActiveCourierTab extends StatelessWidget {
  const _ActiveCourierTab({
    required this.load,
    required this.awaiting,
    required this.onNext,
    required this.onCall,
  });

  final Future<List<CarpetWashOrder>> Function() load;

  /// Мижоз тасдиғи кутилаётган вазифалар (`id → status`).
  final Map<String, String> awaiting;
  final _TaskAction onNext;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    return CourierTaskList<CarpetWashOrder>(
      load: load,
      emptyText: context.tr('carpet_no_active_tasks'),
      // Кутиш давомида рўйхат ўзи янгиланади: мижоз тасдиқласа вазифа ўтади.
      autoRefresh: awaiting.isNotEmpty,
      itemBuilder: (context, order, reload) {
        final isPickup =
            order.status == CarpetWashOrder.statusPickupInDelivery;
        final hasArrived = isPickup
            ? order.pickupArrivedAt != null
            : order.returnArrivedAt != null;
        final waiting = awaiting[order.id] == order.status;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPickup
                    ? context.tr('carpet_pickup_in_progress')
                    : context.tr('carpet_return_in_progress'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(order.pickupAddress),
              Text('${order.customerName} · ${order.customerPhone}'),
              const SizedBox(height: 10),
              if (waiting) ...[
                const CourierAwaitingNotice(),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onCall(order.customerPhone),
                      icon: const Icon(Icons.call, size: 18),
                      label: Text(context.tr('call_short')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // Кутишда тугма ўчирилади: бир хил амални қайта босиш
                    // хато каби кўринмасин.
                    child: ElevatedButton(
                      onPressed: waiting ? null : () => onNext(order, reload),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brown,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        waiting
                            ? context.tr('customer_confirm_waiting')
                            : !hasArrived
                                ? context.tr('courier_arrived_btn')
                                : isPickup
                                    ? context.tr('carpet_mark_picked_up')
                                    : context.tr('carpet_mark_delivered'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
