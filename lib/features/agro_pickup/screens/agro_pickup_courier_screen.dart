import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/agro_pickup_order.dart';
import '../../../services/agro_pickup_service.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../courier/widgets/courier_task_list.dart';
import '../../customer_confirm/widgets/courier_awaiting_notice.dart';
import '../../../core/utils/user_error.dart';

const _green = AvaLight.ok;

/// Kuryer — sut qabul (olib ketish) vazifalari.
///
/// Рўйхатлар — `courierListAgroTasks` callable. Аввал `agro_pickup_orders`
/// оқимлари эди: `courier` `isStaff()`дан чиқарилгач (D-SERVICE-4 /
/// D-CLEAN-1) қоида уларни capability курьерга рад этарди, «Фаол» таб эса
/// ҲАММА курьерларнинг `pickup_in_delivery` вазифаларини олиб, бегонасини
/// клиентда яширарди.
class AgroPickupCourierScreen extends StatefulWidget {
  const AgroPickupCourierScreen({super.key, this.service});

  final AgroPickupService? service;

  @override
  State<AgroPickupCourierScreen> createState() =>
      _AgroPickupCourierScreenState();
}

class _AgroPickupCourierScreenState extends State<AgroPickupCourierScreen> {
  late final AgroPickupService _service =
      widget.service ?? AgroPickupService();
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
      length: 2,
      child: Scaffold(
        backgroundColor: AvaLight.surface2,
        appBar: AppBar(
          title: Text(context.tr('agro_courier_title')),
          backgroundColor: _green,
          foregroundColor: Colors.white,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: context.tr('agro_courier_ready_tab')),
              Tab(text: context.tr('carpet_active_tab')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReadyTab(
              load: () =>
                  _service.listCourierTasks(AgroPickupService.courierListPickup),
              emptyText: context.tr('agro_courier_no_tasks'),
              actionLabel: context.tr('agro_courier_claim'),
              onAction: (order, reload) => _act(
                () => _service.courierClaimPickup(
                  courierPhone: _phone,
                  orderId: order.id,
                ),
                reload,
              ),
            ),
            _ActiveTab(
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
  /// Сервер `awaitingCustomer: true` қайтарганда тўлади; вазифа ўзгарса
  /// (мижоз тасдиқлади) ёки рўйхатдан чиқса — [_loadActive] тозалайди.
  /// Илова қайта очилса бўш: тугма қайта босилса сервер (идемпотент) яна
  /// `awaitingCustomer` қайтаради.
  final Map<String, String> _awaiting = {};

  Future<List<AgroPickupOrder>> _loadActive() async {
    final list =
        await _service.listCourierTasks(AgroPickupService.courierListActive);
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

  /// «Етиб келдим» → «Олиб кетилди», кейин рўйхатни янгилаш.
  Future<void> _advance(
    AgroPickupOrder order,
    Future<void> Function() reload,
  ) async {
    try {
      if (order.arrivedAt != null) {
        final r = await _service.courierMarkPickedUp(
          courierPhone: _phone,
          orderId: order.id,
        );
        if (r.awaitingCustomer && mounted) {
          setState(() => _awaiting[order.id] = order.status);
        }
      } else {
        await _service.courierMarkArrived(
          courierPhone: _phone,
          orderId: order.id,
        );
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
}

typedef _TaskAction = Future<void> Function(
  AgroPickupOrder order,
  Future<void> Function() reload,
);

/// Олиш учун вазифалар: фақат литр — мижоз маълумоти вазифани олгандан
/// кейин «Фаол» табида.
class _ReadyTab extends StatelessWidget {
  const _ReadyTab({
    required this.load,
    required this.emptyText,
    required this.actionLabel,
    required this.onAction,
  });

  final Future<List<AgroPickupOrder>> Function() load;
  final String emptyText;
  final String actionLabel;
  final _TaskAction onAction;

  @override
  Widget build(BuildContext context) {
    return CourierTaskList<AgroPickupOrder>(
      load: () async => (await load())
          .where((o) => o.productType == AgroPickupOrder.productMilk)
          .toList(),
      emptyText: emptyText,
      itemBuilder: (context, order, reload) => _OrderCard(
        order: order,
        primaryLabel: actionLabel,
        onPrimary: () => onAction(order, reload),
      ),
    );
  }
}

/// Шу курьер олган вазифалар — сервер фақат уникини қайтаради.
class _ActiveTab extends StatelessWidget {
  const _ActiveTab({
    required this.load,
    required this.awaiting,
    required this.onNext,
    required this.onCall,
  });

  final Future<List<AgroPickupOrder>> Function() load;

  /// Мижоз тасдиғи кутилаётган вазифалар (`id → status`).
  final Map<String, String> awaiting;
  final _TaskAction onNext;
  final Future<bool> Function(String phone) onCall;

  @override
  Widget build(BuildContext context) {
    return CourierTaskList<AgroPickupOrder>(
      load: load,
      emptyText: context.tr('carpet_no_active_tasks'),
      // Кутиш давомида рўйхат ўзи янгиланади: мижоз тасдиқласа вазифа ўтади.
      autoRefresh: awaiting.isNotEmpty,
      itemBuilder: (context, order, reload) {
        final hasArrived = order.arrivedAt != null;
        final waiting = awaiting[order.id] == order.status;
        return _OrderCard(
          order: order,
          subtitle: context.tr('agro_courier_pickup_in_progress'),
          primaryLabel: waiting
              ? context.tr('customer_confirm_waiting')
              : hasArrived
                  ? context.tr('agro_courier_mark_picked_up')
                  : context.tr('courier_arrived_btn'),
          // Кутишда тугма ўчирилади: бир хил амални қайта босиш хато каби
          // кўринмасин.
          onPrimary: waiting ? null : () => onNext(order, reload),
          waiting: waiting,
          onCall: () => onCall(order.customerPhone),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.primaryLabel,
    required this.onPrimary,
    this.onCall,
    this.subtitle,
    this.waiting = false,
  });

  final AgroPickupOrder order;
  final String primaryLabel;

  /// `null` — тугма ўчирилган (мижоз тасдиғи кутилмоқда).
  final VoidCallback? onPrimary;

  /// Мижоз тасдиғи кутилмоқда — огоҳлантириш блоки кўрсатилади.
  final bool waiting;

  /// `null` — вазифа ҳали олинмаган: мижоз маълумоти йўқ, қўнғироқ ҳам йўқ.
  final VoidCallback? onCall;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final claimed = onCall != null;
    final primary = ElevatedButton(
      onPressed: onPrimary,
      style: ElevatedButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      child: Text(primaryLabel),
    );
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
          if (subtitle != null) ...[
            Text(
              subtitle!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            '${order.literCount.toStringAsFixed(0)} ${context.tr('milk_liter_label')}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          if (claimed) ...[
            Text(order.pickupAddress),
            Text('${order.customerName} · ${order.customerPhone}'),
            if (order.note.isNotEmpty) Text(order.note),
          ] else
            Text(
              context.tr('courier_task_details_after_claim'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
          const SizedBox(height: 10),
          if (waiting) ...[
            const CourierAwaitingNotice(),
            const SizedBox(height: 10),
          ],
          if (claimed)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(context.tr('call_short')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: primary),
              ],
            )
          else
            SizedBox(width: double.infinity, child: primary),
        ],
      ),
    );
  }
}
