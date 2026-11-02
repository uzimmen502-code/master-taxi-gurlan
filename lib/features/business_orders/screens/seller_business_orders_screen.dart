// Сотувчи: «Менинг бизнесим» буюртмалари — рўйхат (фаол / тарих) ва тафсилот (қабул · рад · тайёр, олиб кетиш
// коди). Рўйхат сўрови: `orders where sellerUid == <ўз телефони> orderBy createdAt desc` (rules шуни талаб
// қилади — [BusinessOrdersRepository.sellerQuerySpec]). Ҳолат ўтишлари фақат серверда (17/44-қоида).
// «Етказилмади» қарорлари — мавжуд умумий [DeliveryFailedDecisionList] (`module: business`, сервер сотувчига
// фақат ўз буюртмаларини беради).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../customer_confirm/widgets/delivery_failed_decision_list.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../widgets/business_order_widgets.dart';

class SellerBusinessOrdersScreen extends StatefulWidget {
  const SellerBusinessOrdersScreen({
    super.key,
    this.sellerUid,
    this.businessId = '',
    this.repository,
    this.initialOrderId = '',
    @visibleForTesting this.showDeliveryFailedDecisions = true,
  });

  /// Сотувчи телефони; бўлмаса — қурилмадаги `user_phone`.
  final String? sellerUid;

  /// Фақат шу объект буюртмалари (эга хабидан очилганда); бўш — ҳамма объектлар.
  final String businessId;
  final BusinessOrdersRepository? repository;

  /// Push'дан: шу буюртма тафсилоти дарҳол очилади.
  final String initialOrderId;
  final bool showDeliveryFailedDecisions;

  @override
  State<SellerBusinessOrdersScreen> createState() => _SellerBusinessOrdersScreenState();
}

class _SellerBusinessOrdersScreenState extends State<SellerBusinessOrdersScreen> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  String? _uid;
  Stream<List<BusinessOrder>>? _stream;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    var uid = widget.sellerUid ?? '';
    if (uid.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        uid = prefs.getString('user_phone') ?? '';
      } catch (_) {}
    }
    uid = canonicalPhoneId(uid);
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _stream = _repo.watchSellerOrders(uid);
    });
    final initial = widget.initialOrderId;
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(initial);
      });
    }
  }

  Future<void> _open(String orderId) => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => SellerBusinessOrderDetailScreen(orderId: orderId, repository: _repo),
      ));

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('biz_order_seller_title'))),
      body: _uid == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
              children: [
                if (widget.showDeliveryFailedDecisions) const DeliveryFailedDecisionList(hideWhenEmpty: true),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('biz_seller_filter_active'),
                      label: Text(context.tr('biz_order_filter_active')),
                      selected: _active,
                      onSelected: (_) => setState(() => _active = true),
                    ),
                    ChoiceChip(
                      key: const ValueKey('biz_seller_filter_history'),
                      label: Text(context.tr('biz_order_filter_history')),
                      selected: !_active,
                      onSelected: (_) => setState(() => _active = false),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<BusinessOrder>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _Empty(text: context.tr('biz_order_seller_load_failed'));
                    }
                    if (!snap.hasData) {
                      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                    }
                    final list = [
                      for (final o in snap.data!)
                        if ((widget.businessId.isEmpty || o.businessId == widget.businessId) && o.isActive == _active) o,
                    ];
                    if (list.isEmpty) {
                      return _Empty(text: context.tr(_active ? 'biz_order_seller_empty_active' : 'biz_order_seller_empty_history'));
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final o in list) ...[
                          _SellerOrderTile(order: o, onTap: () => _open(o.id)),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: context.ava.ink2)),
      );
}

class _SellerOrderTile extends StatelessWidget {
  const _SellerOrderTile({required this.order, required this.onTap});

  final BusinessOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final isNew = o.status == BusinessOrderStatus.placed;
    return Material(
      key: ValueKey('biz_seller_order_${o.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AvaRadius.card),
        side: BorderSide(color: isNew ? c.brand : c.line, width: isNew ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isNew) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(AvaRadius.chip)),
                      child: Text(context.tr('biz_order_new_badge'),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.brandInk)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      o.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: BusinessOrderStatusPill(status: o.status)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [for (final l in o.items) '${l.title} ${bizOrderQtyLabel(context, l.qty, l.priceUnit)}'].join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.inkRow),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.createdAt == null ? '' : bizOrderDateLabel(o.createdAt!),
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                  ),
                  Text(formatMoney(o.itemsTotal), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.ink)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сотувчи: битта буюртма — ҳолатга қараб амаллар.
class SellerBusinessOrderDetailScreen extends StatefulWidget {
  const SellerBusinessOrderDetailScreen({super.key, required this.orderId, this.repository});

  final String orderId;
  final BusinessOrdersRepository? repository;

  @override
  State<SellerBusinessOrderDetailScreen> createState() => _SellerBusinessOrderDetailScreenState();
}

class _SellerBusinessOrderDetailScreenState extends State<SellerBusinessOrderDetailScreen> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  late final Stream<BusinessOrder?> _stream = _repo.watchOrder(widget.orderId);
  Stream<String?>? _code;
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn, String okKey) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fn();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.tr(okKey))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(bizOrderErrorText(context, e)), backgroundColor: context.ava.danger));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    // Диалог ўз контроллерини ўзи юритади (ёпилиш анимацияси пайтида ҳам тирик); `null` — бекор.
    final reason = await showDialog<String>(context: context, builder: (_) => const _RejectDialog());
    if (reason == null || !mounted) return;
    await _run(() => _repo.reject(widget.orderId, reason: reason), 'biz_order_rejected_ok');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('biz_order_title'))),
      body: StreamBuilder<BusinessOrder?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(context.tr('biz_order_seller_load_failed'), textAlign: TextAlign.center));
          }
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final o = snap.data;
          if (o == null) return Center(child: Text(context.tr('err_not_found')));
          return ListView(
            padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(o.businessName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: BusinessOrderStatusPill(status: o.status)),
                ],
              ),
              if (o.createdAt != null) Text(bizOrderDateLabel(o.createdAt!), style: TextStyle(fontSize: 12, color: c.ink2)),
              if (o.userName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(context.tr('biz_order_customer').replaceAll('{name}', o.userName), style: TextStyle(fontSize: 13, color: c.ink)),
              ],
              if (o.status == BusinessOrderStatus.placed && o.acceptDeadlineAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr('biz_order_seller_accept_by').replaceAll('{time}', bizOrderTimeLabel(o.acceptDeadlineAt!)),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.warn),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AvaRadius.card),
                  border: Border.all(color: c.line),
                ),
                child: BusinessOrderSummary(order: o, showCashAtDoor: false),
              ),
              if (o.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                BizOrderNotice(icon: Icons.notes_rounded, text: o.note, color: c.ink2, background: c.surface2),
              ],
              const SizedBox(height: 12),
              ..._actions(context, o),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _actions(BuildContext context, BusinessOrder o) {
    final c = context.ava;
    final rejectBtn = OutlinedButton(
      key: const ValueKey('biz_seller_reject'),
      onPressed: _busy ? null : _reject,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.danger,
        side: BorderSide(color: c.danger),
        minimumSize: const Size.fromHeight(48),
      ),
      child: Text(context.tr('biz_order_reject')),
    );
    FilledButton primary(String key, String label, Future<void> Function() fn, String okKey) => FilledButton(
          key: ValueKey(key),
          onPressed: _busy ? null : () => _run(fn, okKey),
          style: FilledButton.styleFrom(
            backgroundColor: c.brand,
            foregroundColor: c.brandInk,
            minimumSize: const Size.fromHeight(48),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    final courierLine = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BizOrderNotice(
        icon: Icons.delivery_dining_rounded,
        text: context.tr(o.hasCourier ? 'biz_order_courier_assigned' : 'biz_order_waiting_courier'),
        color: c.brandText,
        background: c.brandSoft,
      ),
    );
    switch (o.status) {
      case BusinessOrderStatus.placed:
        return [
          primary('biz_seller_accept', context.tr('biz_order_accept'), () => _repo.accept(o.id), 'biz_order_accepted_ok'),
          const SizedBox(height: 8),
          rejectBtn,
        ];
      case BusinessOrderStatus.accepted:
        return [
          courierLine,
          primary('biz_seller_ready', context.tr('biz_order_ready'), () => _repo.markReady(o.id), 'biz_order_ready_ok'),
          const SizedBox(height: 8),
          rejectBtn,
        ];
      case BusinessOrderStatus.ready:
        _code ??= _repo.watchPickupCode(o.id);
        return [
          courierLine,
          _PickupCodeCard(code: _code!, buyout: o.itemsTotal),
          const SizedBox(height: 8),
          rejectBtn,
        ];
      case BusinessOrderStatus.picked:
      case BusinessOrderStatus.arrived:
        return [
          BizOrderNotice(
            icon: Icons.local_shipping_outlined,
            text: context.tr(o.deliveryFailedPending ? 'biz_order_seller_failed_pending' : 'biz_order_seller_in_delivery'),
            color: c.brandText,
            background: c.brandSoft,
          ),
        ];
      default:
        return const [];
    }
  }
}

/// Рад этиш сабаби (ихтиёрий). Натижа — сабаб матни (бўш бўлиши мумкин); бекор — `null`.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('biz_order_reject_title')),
      content: TextField(
        key: const ValueKey('biz_seller_reject_reason'),
        controller: _ctrl,
        maxLength: 200,
        maxLines: 2,
        decoration: InputDecoration(hintText: context.tr('biz_order_reject_hint')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          key: const ValueKey('biz_seller_reject_confirm'),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text(context.tr('biz_order_reject')),
        ),
      ],
    );
  }
}

class _PickupCodeCard extends StatelessWidget {
  const _PickupCodeCard({required this.code, required this.buyout});

  final Stream<String?> code;
  final int buyout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('biz_seller_pickup_code'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.brand, width: 1.5),
      ),
      child: Column(
        children: [
          Text(context.tr('biz_order_pickup_code_title'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.ink2)),
          const SizedBox(height: 6),
          StreamBuilder<String?>(
            stream: code,
            builder: (context, snap) {
              final v = snap.data;
              return Text(
                v == null || v.isEmpty ? '— — — —' : v,
                key: const ValueKey('biz_seller_pickup_code_value'),
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 10, color: c.ink),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('biz_order_pickup_code_hint').replaceAll('{amount}', formatMoney(buyout)),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.ink),
          ),
        ],
      ),
    );
  }
}
