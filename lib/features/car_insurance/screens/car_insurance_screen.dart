import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/car/car_edit_dialog.dart';
import '../car_insurance_service.dart';

/// «Автомобил суғуртаси» (эга 2026-11-28): машина · суғурта муддати (эслатма 4/3 кун) · машина рағбати
/// (бонус ёки мой дастури) · ариза ва тўлов (ҳамён/бонус/чегирма — серверда) · менинг аризаларим ва полис.
/// «Суғурталанган» белгиси ҲЕЧ ҚАЕРДА йўқ (эга).
class CarInsuranceScreen extends StatefulWidget {
  const CarInsuranceScreen({super.key, required this.phone, this.service, this.requestsStream});

  /// Телефон (исталган формат) — ичида `canonicalPhoneId`.
  final String phone;
  final CarInsuranceService? service;

  /// Тест учун: аризалар оқими (бўлмаса Firestore `insurance_requests where uid == <ўзим>`).
  final Stream<List<InsuranceRequest>>? requestsStream;

  @override
  State<CarInsuranceScreen> createState() => _CarInsuranceScreenState();
}

/// Ҳолат номи калити.
String insuranceStatusKey(String status) =>
    kInsuranceStatuses.contains(status) ? 'ins_status_$status' : 'ins_status_requested';

class _CarInsuranceScreenState extends State<CarInsuranceScreen> {
  late final CarInsuranceService _svc = widget.service ?? CarInsuranceService();
  late Future<InsuranceState> _state = _svc.myState();
  late final Stream<List<InsuranceRequest>> _requests = widget.requestsStream ?? _watchRequests();
  bool _busy = false;
  String _policyType = 'osago';
  String? _vehicleType;
  int? _term;

  /// schema 2: фойдаланувчи тузатган ҳудуд (null — профилдан), МДҲ рақамли, ҳайдовчилар.
  String? _zone;
  bool _cis = false;
  String? _scope;
  String? _pendingKey;
  bool? _remindersOptIn;

  String get _phone => canonicalPhoneId(widget.phone);

  Stream<List<InsuranceRequest>> _watchRequests() => FirebaseFirestore.instance
      .collection('insurance_requests')
      .where('uid', isEqualTo: _phone)
      .limit(30)
      .snapshots()
      .map((s) {
        final list = [for (final d in s.docs) InsuranceRequest.fromMap(d.id, d.data())];
        list.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
        return list;
      });

  void _reload() => setState(() => _state = _svc.myState());

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _err(Object e) {
    final x = insuranceErrorOf(e, context.contentLang);
    debugPrint('[CarInsurance] ${x.code} ${x.code == 'UNKNOWN' ? e : ''}');
    return x.message ?? context.tr('ins_err_generic');
  }

  Future<void> _run(Future<void> Function() job, {String? okKey}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (okKey != null && mounted) _toast(context.tr(okKey));
    } catch (e) {
      if (mounted) _toast(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _policyName(String t) => context.tr(t == 'kasko' ? 'ins_policy_kasko' : 'ins_policy_osago');
  String _vehicleName(String t) => context.tr('ins_vehicle_$t');
  String _termName(int m) => context.tr('ins_term_months').replaceAll('{n}', '$m');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ins_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: FutureBuilder<InsuranceState>(
        future: _state,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(onPressed: _reload, child: Text(context.tr('ins_err_retry'))),
            );
          }
          final s = snap.data;
          if (s == null) return const Center(child: CircularProgressIndicator());
          if (!s.available) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('ins_not_available'), key: const ValueKey('ins_not_available'), textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _state;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _carCard(s),
                _expiryCard(s),
                _offerCard(s),
                _requestCard(s),
                _myRequests(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section({required Widget child, Key? key}) => Card(
        key: key,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  Widget _title(String text, IconData icon) => Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ],
      );

  // ── Машина ──
  Widget _carCard(InsuranceState s) {
    final name = [s.carBrand, s.carModel, if (s.carYear > 0) '${s.carYear}'].where((x) => x.isNotEmpty).join(' ');
    return _section(
      key: const ValueKey('ins_car'),
      child: Row(
        children: [
          Icon(Icons.directions_car_filled, size: 34, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.carComplete && name.isNotEmpty ? name : context.tr('ins_car_none'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (s.carPlate.isNotEmpty) Text(s.carPlate, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('ins_car_edit'),
            onPressed: () async {
              final saved = await showCarEditDialog(context, uid: _phone);
              if (saved == true && mounted) _reload();
            },
            child: Text(context.tr(s.carComplete ? 'ins_car_edit' : 'ins_car_add')),
          ),
        ],
      ),
    );
  }

  // ── Суғурта муддати + эслатма ──
  Widget _expiryCard(InsuranceState s) {
    final left = insuranceDaysLeft(s.expiresOn, DateTime.now());
    final optIn = _remindersOptIn ?? s.remindersOptIn;
    return _section(
      key: const ValueKey('ins_expiry'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context.tr('ins_expiry_title'), Icons.event_available),
          const SizedBox(height: 8),
          Text(
            s.expiresOn.isEmpty
                ? context.tr('ins_expiry_none')
                : context
                    .tr(left != null && left < 0 ? 'ins_expiry_passed' : 'ins_expiry_value')
                    .replaceAll('{policy}', _policyName(s.policyType))
                    .replaceAll('{date}', insuranceDisplayDate(s.expiresOn))
                    .replaceAll('{days}', '${left ?? 0}'),
            key: const ValueKey('ins_expiry_text'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('ins_expiry_set'),
              onPressed: _busy ? null : () => _editExpiry(s),
              icon: const Icon(Icons.edit_calendar),
              label: Text(context.tr(s.expiresOn.isEmpty ? 'ins_expiry_add' : 'ins_expiry_change')),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('ins_reminders'),
            contentPadding: EdgeInsets.zero,
            value: optIn,
            title: Text(context.tr('ins_reminders')),
            onChanged: (v) async {
              setState(() => _remindersOptIn = v);
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_phone)
                    .set({'insuranceRemindersOptIn': v}, SetOptions(merge: true));
              } catch (e) {
                if (!mounted) return;
                setState(() => _remindersOptIn = !v);
                _toast(context.tr('ins_err_generic'));
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editExpiry(InsuranceState s) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: s.expiresOn.isNotEmpty ? DateTime.tryParse(s.expiresOn) ?? now : now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3 * 365)),
    );
    if (picked == null || !mounted) return;
    var type = s.policyType.isEmpty ? 'osago' : s.policyType;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(context.tr('ins_expiry_type')),
          content: Wrap(
            spacing: 8,
            children: [
              for (final t in const ['osago', 'kasko'])
                ChoiceChip(label: Text(_policyName(t)), selected: type == t, onSelected: (_) => set(() => type = t)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ins_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('ins_save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _svc.setExpiry(expiresOn: insuranceDateKey(picked), policyType: type);
      _reload();
    }, okKey: 'ins_saved');
  }

  // ── Машина рағбати (бонус ёки мой дастури) ──
  Widget _offerCard(InsuranceState s) {
    final e = s.enrollment;
    final c = s.campaign;
    final prog = insuranceOilProgress(e);
    if (prog != null) {
      return _section(
        key: const ValueKey('ins_oil_progress'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context.tr('ins_oil_title'), Icons.oil_barrel),
            const SizedBox(height: 8),
            Text(
              prog.pct > 0
                  ? context
                      .tr('ins_oil_progress_ready')
                      .replaceAll('{n}', '${prog.n}')
                      .replaceAll('{goal}', '${prog.goal}')
                      .replaceAll('{pct}', '${prog.pct}')
                  : context
                      .tr(e!.discountUsed ? 'ins_oil_used' : 'ins_oil_progress')
                      .replaceAll('{n}', '${prog.n}')
                      .replaceAll('{goal}', '${prog.goal}'),
              key: const ValueKey('ins_oil_progress_text'),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: prog.goal == 0 ? 0 : prog.n / prog.goal, color: AppColors.primary),
          ],
        ),
      );
    }
    if (e != null && e.option == 'bonus') {
      return _section(
        key: const ValueKey('ins_bonus_taken'),
        child: _title(context.tr('ins_offer_bonus_taken'), Icons.card_giftcard),
      );
    }
    if (c == null || e != null) return const SizedBox.shrink();
    final oilText = [
      for (final st in c.oilSteps)
        context.tr('ins_offer_oil_step').replaceAll('{n}', '${st.count}').replaceAll('{pct}', '${st.pct}'),
    ].join(' · ');
    return _section(
      key: const ValueKey('ins_offer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context.tr('ins_offer_title'), Icons.redeem),
          const SizedBox(height: 4),
          Text(context.tr('ins_offer_sub'), style: TextStyle(color: Colors.grey.shade700)),
          if (!s.carComplete) ...[
            const SizedBox(height: 8),
            Text(context.tr('ins_car_required'), style: TextStyle(color: Colors.red.shade700)),
          ],
          if (c.bonusEnabled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('ins_offer_bonus'),
              onPressed: _busy || !s.carComplete ? null : () => _choose('bonus', context.tr('ins_offer_bonus').replaceAll('{amount}', formatMoney(c.bonusAmount))),
              icon: const Icon(Icons.card_giftcard),
              label: Text(context.tr('ins_offer_bonus').replaceAll('{amount}', formatMoney(c.bonusAmount))),
            ),
          ],
          if (c.oilEnabled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('ins_offer_oil'),
              onPressed: _busy || !s.carComplete ? null : () => _choose('oil', '${context.tr('ins_offer_oil')}: $oilText'),
              icon: const Icon(Icons.oil_barrel),
              label: Text('${context.tr('ins_offer_oil')}: $oilText'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choose(String option, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('ins_offer_confirm_title')),
        content: Text(context.tr('ins_offer_confirm').replaceAll('{option}', label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ins_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('ins_offer_choose'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _svc.chooseCarOffer(option);
      _reload();
    }, okKey: option == 'bonus' ? 'ins_offer_bonus_done' : 'ins_offer_oil_done');
  }

  // ── Янги ариза ──
  Widget _requestCard(InsuranceState s) {
    final types = insuranceDistinct(s.options.map((o) => o.policyType));
    if (s.options.isEmpty) {
      return _section(key: const ValueKey('ins_no_prices'), child: Text(context.tr('ins_no_prices')));
    }
    if (s.tariffSchema >= 2) return _zoneRequestCard(s, types);
    final policy = types.contains(_policyType) ? _policyType : types.first;
    final forPolicy = s.options.where((o) => o.policyType == policy).toList();
    final vehicles = insuranceDistinct(forPolicy.map((o) => o.vehicleType));
    final vehicle = vehicles.contains(_vehicleType) ? _vehicleType! : vehicles.first;
    final terms = forPolicy.where((o) => o.vehicleType == vehicle).toList();
    final opt = terms.firstWhere((o) => o.termMonths == _term, orElse: () => terms.first);
    return _section(
      key: const ValueKey('ins_request'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context.tr('ins_request_title'), Icons.shield_outlined),
          const SizedBox(height: 10),
          if (types.length > 1)
            Wrap(spacing: 8, children: [
              for (final t in types)
                ChoiceChip(
                  key: ValueKey('ins_policy_$t'),
                  label: Text(_policyName(t)),
                  selected: policy == t,
                  onSelected: (_) => setState(() => _policyType = t),
                ),
            ]),
          const SizedBox(height: 6),
          Text(context.tr('ins_vehicle_label'), style: TextStyle(color: Colors.grey.shade700)),
          Wrap(spacing: 8, children: [
            for (final v in vehicles)
              ChoiceChip(
                key: ValueKey('ins_vehicle_$v'),
                label: Text(_vehicleName(v)),
                selected: vehicle == v,
                onSelected: (_) => setState(() => _vehicleType = v),
              ),
          ]),
          const SizedBox(height: 6),
          Text(context.tr('ins_term_label'), style: TextStyle(color: Colors.grey.shade700)),
          Wrap(spacing: 8, children: [
            for (final o in terms)
              ChoiceChip(
                key: ValueKey('ins_term_${o.termMonths}'),
                label: Text(_termName(o.termMonths)),
                selected: opt.termMonths == o.termMonths,
                onSelected: (_) => setState(() => _term = o.termMonths),
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            context.tr('ins_price').replaceAll('{price}', formatMoney(opt.price)),
            key: const ValueKey('ins_price'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          Text(context.tr('ins_request_hint'), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('ins_request_submit'),
              onPressed: _busy || !s.carComplete ? null : () => _submit(opt),
              icon: const Icon(Icons.send),
              label: Text(context.tr(s.carComplete ? 'ins_request_submit' : 'ins_car_required')),
            ),
          ),
        ],
      ),
    );
  }

  /// Эга ОСАГО жадвали (2026-11-28): ҳудуд (профилдан, тузатиш мумкин) · МДҲ рақамли · тоифа · ҳайдовчилар · муддат.
  /// Нарх — олдиндан кўриш; ҳақиқий нархни сервер ҳисоблайди ва аризага ёзади.
  Widget _zoneRequestCard(InsuranceState s, List<String> types) {
    final policy = types.contains(_policyType) ? _policyType : types.first;
    final zone = _cis ? 'cis' : (_zone ?? s.derivedZone);
    final forPolicy = s.options.where((o) => o.policyType == policy).toList();
    final vehicles = insuranceVehiclesFor(forPolicy, policy, zone);
    final vehicle = vehicles.contains(_vehicleType) ? _vehicleType : (vehicles.isEmpty ? null : vehicles.first);
    final scope = _scope ?? 'limited';
    final terms = insuranceDistinct(
      forPolicy.where((o) => o.zone == zone && o.vehicleType == vehicle && o.driverScope == scope).map((o) => '${o.termMonths}'),
    ).map(int.parse).toList();
    final term = terms.contains(_term) ? _term! : (terms.isEmpty ? 0 : terms.first);
    final opt = vehicle == null
        ? null
        : insuranceZoneOption(forPolicy, policyType: policy, zone: zone, vehicleType: vehicle, driverScope: scope, termMonths: term);
    Widget chips(String labelKey, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr(labelKey), style: TextStyle(color: Colors.grey.shade700)),
            Wrap(spacing: 8, children: children),
          ]),
        );
    return _section(
      key: const ValueKey('ins_request'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context.tr('ins_request_title'), Icons.shield_outlined),
          if (types.length > 1)
            Wrap(spacing: 8, children: [
              for (final t in types)
                ChoiceChip(
                  key: ValueKey('ins_policy_$t'),
                  label: Text(_policyName(t)),
                  selected: policy == t,
                  onSelected: (_) => setState(() => _policyType = t),
                ),
            ]),
          SwitchListTile(
            key: const ValueKey('ins_cis'),
            contentPadding: EdgeInsets.zero,
            value: _cis,
            title: Text(context.tr('ins_zone_cis_toggle')),
            onChanged: (v) => setState(() => _cis = v),
          ),
          if (!_cis)
            chips('ins_zone_label', [
              for (final z in const ['tashkent', 'other'])
                ChoiceChip(
                  key: ValueKey('ins_zone_$z'),
                  label: Text(context.tr('ins_zone_$z')),
                  selected: zone == z,
                  onSelected: (_) => setState(() => _zone = z),
                ),
            ]),
          chips('ins_vehicle_label', [
            for (final v in vehicles)
              ChoiceChip(
                key: ValueKey('ins_vehicle_$v'),
                label: Text(_vehicleName(v)),
                selected: vehicle == v,
                onSelected: (_) => setState(() => _vehicleType = v),
              ),
          ]),
          chips('ins_scope_label', [
            for (final d in kInsuranceDriverScopes)
              ChoiceChip(
                key: ValueKey('ins_scope_$d'),
                label: Text(context.tr('ins_scope_$d')),
                selected: scope == d,
                onSelected: (_) => setState(() => _scope = d),
              ),
          ]),
          if (terms.length > 1)
            chips('ins_term_label', [
              for (final m in terms)
                ChoiceChip(
                  key: ValueKey('ins_term_$m'),
                  label: Text(_termName(m)),
                  selected: term == m,
                  onSelected: (_) => setState(() => _term = m),
                ),
            ]),
          const SizedBox(height: 10),
          Text(
            opt == null ? context.tr('ins_no_prices') : context.tr('ins_price').replaceAll('{price}', formatMoney(opt.price)),
            key: const ValueKey('ins_price'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          if (opt != null) Text('${_termName(opt.termMonths)} · ${_policyName(opt.policyType)}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          Text(context.tr('ins_request_hint'), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('ins_request_submit'),
              onPressed: _busy || !s.carComplete || opt == null ? null : () => _submit(opt, zone: _cis || _zone != null ? zone : ''),
              icon: const Icon(Icons.send),
              label: Text(context.tr(s.carComplete ? 'ins_request_submit' : 'ins_car_required')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(InsuranceOption opt, {String zone = ''}) async {
    _pendingKey ??= 'k${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';
    String? requestId;
    await _run(() async {
      final r = await _svc.createRequest(
        policyType: opt.policyType,
        vehicleType: opt.vehicleType,
        termMonths: opt.termMonths,
        idempotencyKey: _pendingKey!,
        zone: zone,
        driverScope: opt.driverScope,
      );
      requestId = r.requestId;
      _pendingKey = null;
    });
    if (requestId != null && mounted) await _payFlow(requestId!);
  }

  Future<void> _payFlow(String requestId) async {
    InsuranceQuote? q;
    await _run(() async => q = await _svc.quote(requestId));
    if (q == null || !mounted) return;
    final quote = q!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('ins_pay_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(context.tr('ins_pay_price'), quote.price),
            if (quote.oilDiscount > 0) _line(context.tr('ins_pay_oil').replaceAll('{pct}', '${quote.oilPct}'), -quote.oilDiscount),
            if (quote.incentive > 0) _line(context.tr('ins_pay_bonus'), -quote.incentive),
            const Divider(),
            _line(context.tr('ins_pay_wallet'), quote.walletDue, bold: true),
            const SizedBox(height: 6),
            Text(
              context.tr('ins_pay_balance').replaceAll('{balance}', formatMoney(quote.walletBalance)),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            if (!quote.sufficient)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(context.tr('ins_pay_insufficient'), style: TextStyle(color: Colors.red.shade700)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ins_later'))),
          if (quote.sufficient)
            FilledButton(
              key: const ValueKey('ins_pay_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('ins_pay_confirm')),
            ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _svc.pay(requestId);
      _reload();
    }, okKey: 'ins_paid_ok');
  }

  Widget _line(String label, int amount, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              amount < 0 ? '−${formatMoney(-amount)}' : formatMoney(amount),
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      );

  // ── Менинг аризаларим ──
  Widget _myRequests() {
    return StreamBuilder<List<InsuranceRequest>>(
      stream: _requests,
      builder: (context, snap) {
        final list = snap.data ?? const <InsuranceRequest>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return _section(
          key: const ValueKey('ins_my_requests'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(context.tr('ins_my_requests'), Icons.receipt_long),
              for (final r in list) _requestTile(r),
            ],
          ),
        );
      },
    );
  }

  Widget _requestTile(InsuranceRequest r) {
    return Padding(
      key: ValueKey('ins_req_${r.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_policyName(r.policyType)} · ${_termName(r.termMonths)} · ${formatMoney(r.price)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (r.zone.isNotEmpty)
            Text(
              '${context.tr('ins_zone_${r.zone == 'cis' ? 'cis_short' : r.zone}')} · ${_vehicleName(r.vehicleType)} · '
              '${context.tr('ins_scope_${r.driverScope == 'unlimited' ? 'unlimited' : 'limited'}')}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          Text(context.tr(insuranceStatusKey(r.status)), style: TextStyle(color: Colors.grey.shade700)),
          if (r.status == 'issued')
            Text(
              context
                  .tr('ins_policy_line')
                  .replaceAll('{number}', r.policyNumber)
                  .replaceAll('{from}', insuranceDisplayDate(r.validFrom))
                  .replaceAll('{to}', insuranceDisplayDate(r.validTo)),
            ),
          Wrap(spacing: 8, children: [
            if (r.status == 'requested') ...[
              TextButton(
                key: ValueKey('ins_req_pay_${r.id}'),
                onPressed: _busy ? null : () => _payFlow(r.id),
                child: Text(context.tr('ins_pay_confirm')),
              ),
              TextButton(
                key: ValueKey('ins_req_cancel_${r.id}'),
                onPressed: _busy ? null : () => _run(() => _svc.cancelMine(r.id), okKey: 'ins_cancelled_ok'),
                child: Text(context.tr('ins_cancel_request')),
              ),
            ],
            if (r.status == 'issued')
              TextButton.icon(
                key: ValueKey('ins_req_policy_${r.id}'),
                onPressed: _busy ? null : () => _openPolicy(r.id),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(context.tr('ins_open_policy')),
              ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openPolicy(String requestId) => _run(() async {
        final url = await _svc.policyLink(requestId);
        final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!ok) throw StateError('LAUNCH_FAILED');
      });
}
