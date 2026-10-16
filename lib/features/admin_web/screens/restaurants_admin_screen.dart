// КАФЕ-РЕСТОРАНЛАР — админ (Б4, docs/kafe_restoran_taklifi_uz.md §11/§15):
//   1. Ресторанлар — аризалар (applied) тасдиқ/рад, фаолларни тўхтатиш/ёпиш
//      (`adminSetRestaurantStatus`, сервер жадвали, audit);
//   2. Буюртмалар — `type == 'restaurant'`, ҳолат фильтри, админ бекор
//      (`adminCancelRestaurantOrder`: 2 % қайтади, курьер маршрутидан олинади);
//   3. Тариф — AVA курьери етказиш нархи, версияли + тарих
//      (`adminSetRestaurantDeliveryPrices`; `settings/restaurant_delivery`
//      клиентдан ЁЗИЛМАЙДИ — қоида);
//   4. Созламалар — модул босқичи (internal/public + синовчилар) ва
//      авто-тасдиқ (`adminSetRestaurantsStage`, `adminSetRestaurantAutoApprove`).
// Ҳамма ёзув СЕРВЕРДА; экран фақат ўқийди ва чақиради (44-банд).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../services/admin_restaurants_service.dart';
import '../utils/restaurant_tariff_draft.dart';
import '../widgets/restaurant_fee_card.dart';

final _dateFmt = DateFormat('dd.MM HH:mm');

String _errText(Object e) => e is AdminRestaurantsException ? e.toString() : '$e';

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Colors.red.shade700 : null,
    duration: Duration(seconds: error ? 8 : 4),
  ));
}

/// Сабаб сўраш (рад/тўхтатиш/бекор) — бўш бўлмасин.
Future<String?> _askReason(BuildContext context, {required String title, String hint = 'Сабаб (мажбурий)'}) async {
  final ctrl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 300,
        maxLines: 3,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            if (t.length < 3) return;
            Navigator.pop(ctx, t);
          },
          child: const Text('Тасдиқлаш'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}

class RestaurantsAdminScreen extends StatefulWidget {
  const RestaurantsAdminScreen({super.key, this.service});

  final AdminRestaurantsService? service;

  @override
  State<RestaurantsAdminScreen> createState() => _RestaurantsAdminScreenState();
}

class _RestaurantsAdminScreenState extends State<RestaurantsAdminScreen> {
  late final AdminRestaurantsService _svc = widget.service ?? AdminRestaurantsService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          title: const Text('🍽 Кафе-ресторанлар', style: TextStyle(fontWeight: FontWeight.bold)),
          // Сариқ AppBar устида Material 3 стандарт танланган таб ранги
          // (`primary`) кўринмайди — бошқа админ экранлари каби `onPrimary`.
          bottom: TabBar(
            isScrollable: true,
            labelColor: AppColors.onPrimary,
            unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.6),
            indicatorColor: AppColors.onPrimary,
            tabs: const [
              Tab(text: 'Ресторанлар'),
              Tab(text: 'Буюртмалар'),
              Tab(text: 'Етказиш тарифи'),
              Tab(text: 'Созламалар'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RestaurantsTab(svc: _svc),
            _OrdersTab(svc: _svc),
            _TariffTab(svc: _svc),
            _SettingsTab(svc: _svc),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. Ресторанлар
// ═══════════════════════════════════════════════════════════════════════════

/// Сервер `RESTAURANT_ADMIN_TRANSITIONS` билан бир хил (restaurant_orders.js).
const _adminTransitions = <String, List<String>>{
  'applied': ['approved', 'rejected'],
  'rejected': ['approved'],
  'approved': ['suspended', 'closed'],
  'suspended': ['approved', 'closed'],
  'closed': [],
};

const _statusLabel = <String, String>{
  'applied': 'Ариза',
  'approved': 'Фаол',
  'rejected': 'Рад этилган',
  'suspended': 'Тўхтатилган',
  'closed': 'Ёпилган',
};

const _actionLabel = <String, String>{
  'approved': 'Тасдиқлаш',
  'rejected': 'Рад этиш',
  'suspended': 'Тўхтатиш',
  'closed': 'Ёпиш',
};

Color _statusColor(String s) => switch (s) {
      'approved' => AvaLight.ok,
      'applied' => AvaLight.warn,
      'suspended' => Colors.orange.shade800,
      'rejected' || 'closed' => AvaLight.danger,
      _ => Colors.grey.shade700,
    };

class _RestaurantsTab extends StatefulWidget {
  const _RestaurantsTab({required this.svc});

  final AdminRestaurantsService svc;

  @override
  State<_RestaurantsTab> createState() => _RestaurantsTabState();
}

class _RestaurantsTabState extends State<_RestaurantsTab> {
  String _filter = 'applied';
  String? _busyId;

  Future<void> _setStatus(Restaurant r, String to) async {
    String reason = '';
    if (to != 'approved') {
      final res = await _askReason(context, title: '${_actionLabel[to]}: ${r.name}');
      if (res == null) return;
      reason = res;
    }
    setState(() => _busyId = r.id);
    try {
      await widget.svc.setStatus(r.id, to, reason: reason);
      if (mounted) _snack(context, '${r.name}: ${_statusLabel[to]}');
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${_errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('restaurants').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        final counts = <String, int>{};
        for (final d in docs) {
          final s = (d.data()['status'] ?? '') as String;
          counts[s] = (counts[s] ?? 0) + 1;
        }
        final shown = docs.where((d) => _filter.isEmpty || d.data()['status'] == _filter).toList();
        return Column(
          children: [
            _FilterBar(
              value: _filter,
              options: {
                '': 'Ҳаммаси (${docs.length})',
                for (final s in _statusLabel.keys) s: '${_statusLabel[s]} (${counts[s] ?? 0})',
              },
              onChanged: (v) => setState(() => _filter = v),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Бу бўлимда ресторан йўқ'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final doc = shown[i];
                        final r = Restaurant.fromDoc(doc);
                        return _RestaurantCard(
                          restaurant: r,
                          raw: doc.data(),
                          busy: _busyId == r.id,
                          onAction: (to) => _setStatus(r, to),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({required this.restaurant, required this.raw, required this.busy, required this.onAction});

  final Restaurant restaurant;
  final Map<String, dynamic> raw;
  final bool busy;
  final void Function(String to) onAction;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final createdAt = (raw['createdAt'] as Timestamp?)?.toDate();
    final statusReason = (raw['statusReason'] ?? '') as String;
    final actions = _adminTransitions[r.status] ?? const <String>[];
    final delivery = switch (r.delivery.mode) {
      'ava_courier' => 'AVA курьери',
      'own_courier' => 'Ўз курьери',
      _ => 'Етказиш йўқ',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(r.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              _Chip(_statusLabel[r.status] ?? r.status, _statusColor(r.status)),
            ]),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _kv('Шакл', switch (r.legalType) { 'yatt' => 'ЯТТ', 'llc' => 'МЧЖ', _ => 'Жисмоний шахс' }),
                _kv('Телефон', r.contactPhone.isEmpty ? '—' : r.contactPhone),
                _kv('Эга', r.ownerUid),
                _kv('Манзил', r.address.isEmpty ? '—' : r.address),
                _kv('Етказиш', '$delivery${r.delivery.pickup ? ' · олиб кетиш' : ''}'),
                _kv('Тўлов', [if (r.payment.prepay) 'олдиндан', if (r.payment.cash) 'нақд'].join(' / ')),
                _kv('Тайёрлаш', '${r.prepTimeMin} дақ'),
                _kv('Мин. буюртма', '${formatPrice(r.minOrderAmount)} сўм'),
                if (r.cuisineTags.isNotEmpty) _kv('Ошхона', r.cuisineTags.join(', ')),
                if (createdAt != null) _kv('Ариза', _dateFmt.format(createdAt)),
                if (statusReason.isNotEmpty) _kv('Сабаб', statusReason),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final to in actions)
                    to == 'approved'
                        ? FilledButton.icon(
                            onPressed: busy ? null : () => onAction(to),
                            icon: const Icon(Icons.check, size: 16),
                            label: Text(_actionLabel[to]!),
                            style: FilledButton.styleFrom(backgroundColor: AvaLight.ok, foregroundColor: Colors.white),
                          )
                        : OutlinedButton.icon(
                            onPressed: busy ? null : () => onAction(to),
                            icon: Icon(to == 'closed' ? Icons.block : Icons.pause_circle_outline, size: 16),
                            label: Text(_actionLabel[to]!),
                            style: OutlinedButton.styleFrom(foregroundColor: _statusColor(to)),
                          ),
                  if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. Буюртмалар
// ═══════════════════════════════════════════════════════════════════════════

const _orderStatusLabel = <String, String>{
  'placed': 'Юборилди',
  'accepted': 'Қабул',
  'ready': 'Тайёр',
  'picked': 'Курьерда',
  'arrived': 'Етиб келди',
  'delivered': 'Етказилди',
  'rejected': 'Рад',
  'cancelled': 'Бекор',
  'delivery_failed': 'Етказиб бўлмади',
};

Color _orderStatusColor(String s) => switch (s) {
      'delivered' => AvaLight.ok,
      'rejected' || 'cancelled' || 'delivery_failed' => AvaLight.danger,
      'placed' => AvaLight.warn,
      _ => AppColors.primaryText,
    };

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.svc});

  final AdminRestaurantsService svc;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  String _filter = '';
  String? _busyId;

  Future<void> _cancel(OrderModel o) async {
    final reason = await _askReason(context, title: 'Буюртмани бекор қилиш (${o.restaurantName})');
    if (reason == null) return;
    setState(() => _busyId = o.id);
    try {
      final refund = await widget.svc.cancelOrder(o.id, reason: reason);
      if (mounted) {
        _snack(context, 'Бекор қилинди${refund > 0 ? ' · 2 % қайтарилди: ${formatPrice(refund)} сўм' : ''}');
      }
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${_errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('type', isEqualTo: 'restaurant')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!.docs.map(OrderModel.fromDoc).toList();
        final counts = <String, int>{};
        for (final o in all) {
          counts[o.restaurantStatus] = (counts[o.restaurantStatus] ?? 0) + 1;
        }
        final shown = all.where((o) => _filter.isEmpty || o.restaurantStatus == _filter).toList();
        return Column(
          children: [
            _FilterBar(
              value: _filter,
              options: {
                '': 'Ҳаммаси (${all.length})',
                for (final s in _orderStatusLabel.keys)
                  if ((counts[s] ?? 0) > 0) s: '${_orderStatusLabel[s]} (${counts[s]})',
              },
              onChanged: (v) => setState(() => _filter = v),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Буюртма йўқ'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _OrderCard(order: shown[i], busy: _busyId == shown[i].id, onCancel: () => _cancel(shown[i])),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busy, required this.onCancel});

  final OrderModel order;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final terminal = RestaurantOrderStatus.isTerminal(o.restaurantStatus);
    final food = switch (o.foodPaymentMethod) {
      'prepay' => 'олдиндан (${o.paymentStatus})',
      'cash_buyout' => 'нақд → курьер (выкуп)',
      'cash_to_restaurant' => 'нақд → ресторан',
      _ => o.foodPaymentMethod,
    };
    final items = o.items.map((e) => '${e.name} ×${e.count}').join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '🍽 ${o.restaurantName}  ·  ${o.createdAt != null ? _dateFmt.format(o.createdAt!) : ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _Chip(_orderStatusLabel[o.restaurantStatus] ?? o.restaurantStatus, _orderStatusColor(o.restaurantStatus)),
            ]),
            const SizedBox(height: 4),
            Text(items, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _kv('ID', o.id),
                _kv('Мижоз', '${o.userName} ${o.userPhone}'.trim()),
                if (o.address.isNotEmpty) _kv('Манзил', o.address),
                _kv('Таом', '${formatPrice(o.itemsTotal)} сўм${o.packagingTotal > 0 ? ' + қадоқ ${formatPrice(o.packagingTotal)}' : ''}'),
                _kv('Етказиш', '${formatPrice(o.deliveryFee)} сўм (${o.deliveryPaymentMethod})'),
                _kv('Жами', '${formatPrice(o.total)} сўм'),
                _kv('Таом пули', food),
                _kv('Режим', o.deliveryMode),
                if ((o.courierId ?? '').isNotEmpty) _kv('Курьер', o.courierId!),
                _kv('AVA 2 %', '${formatPrice(o.avaFeeAmount)} сўм · ${o.avaFeeRefunded ? 'қайтарилган' : o.avaFeeCharged ? 'ечилган' : 'ечилмаган'}'),
                if (o.rejectReason.isNotEmpty) _kv('Сабаб', o.rejectReason),
                if (o.note.isNotEmpty) _kv('Изоҳ', o.note),
              ],
            ),
            if (!terminal) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Бекор қилиш (админ)'),
                        style: OutlinedButton.styleFrom(foregroundColor: AvaLight.danger),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. Етказиш тарифи (версияли)
// ═══════════════════════════════════════════════════════════════════════════

class _TariffTab extends StatefulWidget {
  const _TariffTab({required this.svc});

  final AdminRestaurantsService svc;

  @override
  State<_TariffTab> createState() => _TariffTabState();
}

class _TariffTabState extends State<_TariffTab> {
  RestaurantTariffDraft? _draft;
  final Map<String, TextEditingController> _c = {};
  final _reason = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String initial) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial))..text = initial;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('restaurant_delivery').get();
      final d = RestaurantTariffDraft.fromDoc(doc.data());
      _ctrl('base', d.base);
      _ctrl('perKm', d.perKm);
      _ctrl('nightCoef', d.nightCoef);
      _ctrl('nightStart', d.nightStart);
      _ctrl('nightEnd', d.nightEnd);
      _ctrl('roadFactor', d.roadFactor);
      _ctrl('maxKm', d.maxKm);
      for (final e in d.regions.entries) {
        _ctrl('${e.key}.base', e.value.base);
        _ctrl('${e.key}.perKm', e.value.perKm);
        _ctrl('${e.key}.nightCoef', e.value.nightCoef);
        _ctrl('${e.key}.maxKm', e.value.maxKm);
      }
      if (mounted) setState(() => _draft = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Контроллерлардан қораламага (валидация ва payload — соф мантиқ).
  RestaurantTariffDraft _collect() {
    final d = _draft!;
    d
      ..base = _c['base']!.text
      ..perKm = _c['perKm']!.text
      ..nightCoef = _c['nightCoef']!.text
      ..nightStart = _c['nightStart']!.text
      ..nightEnd = _c['nightEnd']!.text
      ..roadFactor = _c['roadFactor']!.text
      ..maxKm = _c['maxKm']!.text;
    for (final e in d.regions.entries) {
      e.value
        ..base = _c['${e.key}.base']!.text
        ..perKm = _c['${e.key}.perKm']!.text
        ..nightCoef = _c['${e.key}.nightCoef']!.text
        ..maxKm = _c['${e.key}.maxKm']!.text;
    }
    return d;
  }

  Future<void> _save() async {
    final d = _collect();
    final errs = d.validate();
    if (errs.isNotEmpty) {
      _snack(context, errs.join('\n'), error: true);
      return;
    }
    if (_reason.text.trim().length < 3) {
      _snack(context, 'Ўзгариш сабабини ёзинг (аудит учун)', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Тариф v${d.version + 1} сақлансинми?'),
        content: const Text(
          'Янги версия шу заҳоти барча ЯНГИ буюртмаларга қўлланади. Мавжуд '
          'буюртмалар ўз версияси билан қолади. Эски қиймат тарихда сақланади.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сақлаш')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final v = await widget.svc.setDeliveryPrices(d.toPayload(reason: _reason.text));
      if (!mounted) return;
      _reason.clear();
      _snack(context, 'Сақланди: v$v');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${_errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _draft == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Хато: $_error'), TextButton(onPressed: _load, child: const Text('Қайта'))]));
    }
    final d = _draft!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoBar(
          icon: d.isConfigured ? Icons.verified_outlined : Icons.warning_amber_rounded,
          color: d.isConfigured ? AvaLight.ok : AvaLight.warn,
          text: d.isConfigured
              ? 'Жорий тариф: v${d.version}${d.updatedBy.isNotEmpty ? ' · ${d.updatedBy}' : ''}. Нарх: 1 км гача базавий + ҳар кейинги км, тунда коэффициент, 500 сўмга яхлитлаш; масофа — йўл × коэффициент.'
              : 'Тариф ҳали созланмаган — AVA курьери билан етказиш ишламайди (TARIFF_NOT_CONFIGURED). Рақамлар — эга қарори.',
        ),
        const SizedBox(height: 12),
        const Text('Умумий (ҳамма ҳудуд)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _NumField(ctrl: _c['base']!, label: 'Базавий (1 км гача), сўм', width: 200),
            _NumField(ctrl: _c['perKm']!, label: 'Ҳар кейинги км, сўм', width: 200),
            _NumField(ctrl: _c['nightCoef']!, label: 'Тун коэф. (1..3)', width: 140, decimal: true),
            _NumField(ctrl: _c['nightStart']!, label: 'Тун бошланиши (соат)', width: 160),
            _NumField(ctrl: _c['nightEnd']!, label: 'Тун тугаши (соат)', width: 160),
            _NumField(ctrl: _c['roadFactor']!, label: 'Йўл коэф. (1..2)', width: 140, decimal: true),
            _NumField(ctrl: _c['maxKm']!, label: 'Макс. масофа, км', width: 150),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Ҳудудлар (ёқилгани умумийни қоплайди)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final e in d.regions.entries)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(kRestaurantTariffRegions[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    value: e.value.enabled,
                    onChanged: (v) => setState(() => e.value.enabled = v),
                  ),
                  if (e.value.enabled)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _NumField(ctrl: _c['${e.key}.base']!, label: 'Базавий, сўм', width: 160),
                        _NumField(ctrl: _c['${e.key}.perKm']!, label: 'Ҳар км, сўм', width: 160),
                        _NumField(ctrl: _c['${e.key}.nightCoef']!, label: 'Тун коэф.', width: 120, decimal: true),
                        _NumField(ctrl: _c['${e.key}.maxKm']!, label: 'Макс. км', width: 110),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _reason,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Ўзгариш сабаби (аудит)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text('Сақлаш (v${d.version + 1})'),
          ),
          const SizedBox(width: 12),
          TextButton.icon(onPressed: _saving ? null : _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Қайта юклаш')),
        ]),
        const SizedBox(height: 20),
        const Text('Тарих', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('restaurant_delivery_tariffs').orderBy('version', descending: true).limit(20).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Text('Тарих хатоси: ${snap.error}');
            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) return const Text('Ҳали ўзгариш йўқ', style: TextStyle(color: Colors.grey));
            return Column(
              children: [
                for (final h in docs)
                  Builder(builder: (_) {
                    final m = h.data();
                    final at = (m['changedAt'] as Timestamp?)?.toDate();
                    final prev = m['previous'] is Map ? Map<String, dynamic>.from(m['previous'] as Map) : const <String, dynamic>{};
                    return ListTile(
                      dense: true,
                      leading: Text('v${m['version']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      title: Text('${formatPrice((m['base'] as num?) ?? 0)} + ${formatPrice((m['perKm'] as num?) ?? 0)}/км · тун ×${m['nightCoef']} · макс ${m['maxKm']} км'
                          '${prev['base'] != null ? '   (эски: ${formatPrice(prev['base'] as num)} + ${formatPrice((prev['perKm'] as num?) ?? 0)}/км)' : ''}'),
                      subtitle: Text('${at != null ? _dateFmt.format(at) : ''} · ${m['changedBy'] ?? ''}${(m['reason'] ?? '').toString().isNotEmpty ? ' · ${m['reason']}' : ''}'),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. Созламалар — босқич, авто-тасдиқ
// ═══════════════════════════════════════════════════════════════════════════

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.svc});

  final AdminRestaurantsService svc;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _testers = TextEditingController();
  String? _stage;
  bool _stageLoaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _testers.dispose();
    super.dispose();
  }

  Future<void> _saveStage() async {
    final stage = _stage;
    if (stage == null) return;
    final ids = _testers.text.split(RegExp(r'[\s,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (stage == 'public') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Модул ҲАММАГА очилсинми?'),
          content: const Text('`public` босқичда барча фойдаланувчилар ресторан очади ва буюртма беради. Бош экрандаги кўриниш — «Ҳудудлар ва хизматлар» модул созламасига ҳам боғлиқ.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Очиш')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final saved = await widget.svc.setStage(stage: stage, testerIds: ids);
      if (mounted) _snack(context, 'Босқич: $stage · синовчилар: ${saved.length}');
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${_errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAuto(bool enabled) async {
    setState(() => _busy = true);
    try {
      await widget.svc.setAutoApprove(enabled);
    } catch (e) {
      if (mounted) _snack(context, 'Хато: ${_errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Модул босқичи (42-банд)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('module_config').doc('restaurants_all').snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? const <String, dynamic>{};
            final cfg = data['restaurants'] is Map ? Map<String, dynamic>.from(data['restaurants'] as Map) : const <String, dynamic>{};
            final serverStage = cfg['stage'] == 'public' ? 'public' : 'internal';
            final serverTesters = ((cfg['testerIds'] as List?) ?? const []).map((e) => e.toString()).toList();
            if (!_stageLoaded && snap.hasData) {
              _stageLoaded = true;
              _stage = serverStage;
              _testers.text = serverTesters.join('\n');
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Серверда: $serverStage · синовчилар: ${serverTesters.length}${data['enabled'] == false ? ' · МОДУЛ ЎЧИҚ (enabled=false)' : ''}',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    for (final opt in const [
                      ('internal', 'INTERNAL — фақат синовчилар (ресторан очиш, буюртма бериш)'),
                      ('public', 'PUBLIC — ҳамма'),
                    ])
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_stage == opt.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: _stage == opt.$1 ? AppColors.primaryText : Colors.grey),
                        title: Text(opt.$2),
                        onTap: () => setState(() => _stage = opt.$1),
                      ),
                    TextField(
                      controller: _testers,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Синовчилар телефони (ҳар қаторда битта; 998… ёки 9 рақам)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy || _stage == null ? null : _saveStage,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Босқични сақлаш'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        const Text('AVA ҳақи ва тун коэффициенти', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        RestaurantFeeCard(svc: widget.svc),
        const SizedBox(height: 18),
        const Text('Ресторан аризаси', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('settings').doc('app').snapshots(),
          builder: (context, snap) {
            final auto = snap.data?.data()?['restaurantAutoApprove'] == true;
            return _InfoBar(
              icon: auto ? Icons.flash_on : Icons.admin_panel_settings,
              color: auto ? AvaLight.ok : Colors.orange.shade800,
              text: auto
                  ? 'АВТО: янги ресторан дарҳол фаол (approved) бўлади.'
                  : 'ҚЎЛДА: янги ресторан «Ариза» бўлиб туради, админ тасдиқлайди.',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(onPressed: _busy || !auto ? null : () => _setAuto(false), child: const Text('ҚЎЛДА')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy || auto ? null : () => _setAuto(true), child: const Text('АВТО')),
              ]),
            );
          },
        ),
        const SizedBox(height: 18),
        const Text('Сервер қоидалари (кодда, ўзгартириш — деплой; AVA ҳақи — юқорида)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const _InfoBar(
          icon: Icons.info_outline,
          color: AppColors.primaryText,
          text: 'AVA ҳақи — таом суммасининг фоизи (стандарт 2 %, эга қарори D-REST-2; юқоридаги «AVA ҳақи» карточкасида ўзгартирилади), ресторан эгаси ҳамёнидан қабулда ечилади, етказилмаса қайтади. '
              'Ресторан жавоб муддати 5 дақ (ўтса — рад, 3 та кетма-кет → 30 дақ пауза). '
              'Олиб кетиш коди — 4 рақам, 5 уриниш. Мижоз 2 марта эшикда олмаса — 30 кун фақат олдиндан тўлов.',
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Умумий виджетлар
// ═══════════════════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.options, required this.onChanged});

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final e in options.entries)
              ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

Widget _kv(String k, String v) => RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: Colors.black87),
        children: [
          TextSpan(text: '$k: ', style: TextStyle(color: Colors.grey.shade600)),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.icon, required this.color, required this.text, this.trailing});

  final IconData icon;
  final Color color;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.ctrl, required this.label, required this.width, this.decimal = false});

  final TextEditingController ctrl;
  final String label;
  final double width;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'))],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }
}
