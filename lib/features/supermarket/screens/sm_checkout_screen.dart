import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_selector.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../repositories/user_repository.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../data/supermarket_repository.dart';
import '../domain/sm_access.dart';
import '../domain/sm_holiday.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_gift_form.dart';
import '../widgets/sm_widgets.dart';

/// 5-экран: расмийлаштириш — манзил, кун + вақт (сервердан), ҳамён тўлови.
///
/// Иккиламчи буюртма бўлмаслиги учун (21-банд): `clientRequestId` бир уриниш учун БИР марта
/// ясалади ([IdempotencyKeys]); тармоқ хатосида «Қайта уриниш» ўша калит билан кетади, аниқ
/// натижадан (муваффақият / сервер рад этди) кейин янгиланади. Юбориш пайтида тугма ўчиқ.
class SmCheckoutScreen extends StatefulWidget {
  const SmCheckoutScreen({
    super.key,
    required this.controller,
    @visibleForTesting this.balance,
    @visibleForTesting this.keys,
    @visibleForTesting this.pickArea,
    @visibleForTesting this.openTopUp,
    this.holiday,
    @visibleForTesting this.today,
    @visibleForTesting this.incentive,
  });

  /// Тест учун; бўлмаса — `users/{uid}.incentiveBalance` (AVA бонуси). Қанча қўлланиши — СЕРВЕР қарори
  /// (эга 2026-11-27: бонус ҳамма супермаркет буюртмасида).
  final Stream<int>? incentive;

  final SupermarketController controller;

  /// «Байрам саватчаси» оқими (эга 2026-11-26): бўлса — совға блоки ва 14 кунлик сана танлови кўрсатилади.
  /// `null` — расмийлаштириш аввалгидек (бугун/эртага).
  final SmHolidayCheckout? holiday;

  /// Тест учун; бўлмаса — Тошкент санаси.
  final DateTime? today;

  /// Тест учун; бўлмаса — мавжуд [walletBalanceStream].
  final Stream<int>? balance;
  final IdempotencyKeys? keys;
  final Future<GeoArea?> Function(BuildContext context)? pickArea;
  final void Function(BuildContext context, int shortfall)? openTopUp;

  @override
  State<SmCheckoutScreen> createState() => _SmCheckoutScreenState();
}

class _SmCheckoutScreenState extends State<SmCheckoutScreen> {
  static const _scope = 'sm_order';

  late final IdempotencyKeys _keys = widget.keys ?? IdempotencyKeys();
  late final Stream<int> _balance = widget.balance ?? walletBalanceStream();
  final _mahalla = TextEditingController();
  final _street = TextEditingController();
  final _house = TextEditingController();
  final _landmark = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _errorKey;

  /// Сервер берган матн (`details.messages`) — бўлса калит ўрнига кўрсатилади.
  Map<String, String> _errorMessages = const {};

  SupermarketController get _c => widget.controller;

  // ── Байрам оқими ──
  bool get _holiday => widget.holiday != null;
  late final DateTime _today = widget.today ?? smTashkentDate();
  DateTime? _date;
  late bool _asGift = widget.holiday?.asGift ?? false;
  late final _giftName = TextEditingController(text: widget.holiday?.recipientName ?? '');
  late final _giftPhone = TextEditingController(text: widget.holiday?.recipientPhone ?? '');
  final _giftMsg = TextEditingController();
  bool _showGiftErrors = false;

  SmGift get _gift => SmGift(recipientName: _giftName.text, recipientPhone: _giftPhone.text, message: _giftMsg.text);

  int get _maxDays => _c.access.maxAheadDays > 0 ? _c.access.maxAheadDays : kSmDeliveryMaxDays;

  /// Эга 2026-11-28: вақт оралиғи ЙЎҚ — совға/байрамда фақат сана (бугун..+maxDays; сервер ҳам текширади).
  List<DateTime> get _dates => smDeliveryDates(_today, maxDays: _maxDays);

  void _pickDefaultDate() {
    final ds = _dates;
    if (_date == null || !ds.any((d) => smIsoDate(d) == smIsoDate(_date!))) {
      _date = ds.isEmpty ? null : ds.first;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_holiday) _pickDefaultDate();
    _prefillPhone();
    // Танланган туман учун рухсат ва вақтлар — сервердан (getSupermarketAccess({districtId})).
    _refreshAccess();
    // Битта обуна: баланс ҳам кўрсатилади, ҳам тасдиқ тугмасини бошқаради (етмаса — ўчиқ, тўлдириш тугмаси).
    _balanceSub = _balance.listen((b) {
      if (mounted) setState(() => _lastBalance = b);
    });
    _incentiveSub = (widget.incentive ?? smIncentiveBalanceStream()).listen((v) {
      if (mounted) setState(() => _incentive = v < 0 ? 0 : v);
    }, onError: (Object e) => debugPrint('[Supermarket] incentive balance: $e'));
  }

  StreamSubscription<int>? _balanceSub;
  int? _lastBalance;
  StreamSubscription<int>? _incentiveSub;
  int _incentive = 0;

  /// Сервер «маблағ етмайди» деса — етишмаган сумма (`details.required - details.balance`), бўлмаса 0.
  int _serverShort = 0;

  /// Бонус ҚОПЛАШИ МУМКИН бўлган энг кўп сумма (тахмин: бонус қолдиғи, товар суммасидан ошмайди). Ҳақиқийси
  /// серверда (туркум/улуш чегаралари) — етмаса сервер рад этади ва тўлдириш тугмаси чиқади.
  int get _bonusEstimate => smBonusEstimate(incentive: _incentive, goodsTotal: _c.totals.goodsTotal);

  /// Ҳамёнда етишмаётган сумма (баланс маълум бўлса; бонус ҳисобга олинган, тахминий — якуний текширув серверда).
  int get _shortfall => _lastBalance == null ? 0 : _c.totals.holdEstimate - _bonusEstimate - _lastBalance!;

  Future<void> _refreshAccess() async {
    final d = _c.deliveryArea.districtId;
    if (d.isEmpty) return;
    await _c.refreshAccessFor(d, withDates: _holiday);
    if (!mounted) return;
    setState(() {
      if (_holiday) _pickDefaultDate();
    });
  }

  Future<void> _prefillPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString('user_phone') ?? '';
      if (mounted && _phone.text.isEmpty) _phone.text = p;
    } catch (_) {}
  }

  @override
  void dispose() {
    _balanceSub?.cancel();
    _incentiveSub?.cancel();
    for (final t in [_mahalla, _street, _house, _landmark, _phone, _giftName, _giftPhone, _giftMsg]) {
      t.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _address() {
    String v(TextEditingController t) => t.text.trim();
    return {
      'districtId': _c.deliveryArea.districtId,
      if (v(_mahalla).isNotEmpty) 'mahalla': v(_mahalla),
      if (v(_street).isNotEmpty) 'street': v(_street),
      if (v(_house).isNotEmpty) 'house': v(_house),
      if (v(_landmark).isNotEmpty) 'landmark': v(_landmark),
      'phone': v(_phone),
    };
  }

  bool get _giftOk => !_holiday || !_asGift || smGiftProblems(_gift).isEmpty;

  /// Совғадан ташқари ҳамма шартлар (тугма шу билан ёқилади; совға хатоси босилганда кўрсатилади).
  bool get _baseOk =>
      _c.access.allowed &&
      _c.deliveryArea.districtId.isNotEmpty &&
      phoneDigits(_phone.text).length >= 9 &&
      (!_holiday || (_date != null && smDeliveryDateOk(_date!, _today, maxDays: _maxDays))) &&
      !_c.cart.isEmpty;

  bool get _formOk => _baseOk && _giftOk;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_giftOk) {
      setState(() => _showGiftErrors = true);
      return;
    }
    if (!_formOk) return;
    setState(() {
      _submitting = true;
      _errorKey = null;
      _serverShort = 0;
    });
    final h = widget.holiday;
    final payload = h != null
        ? smHolidayOrderPayload(
            clientRequestId: _keys.keyFor(_scope),
            cart: _c.cart,
            address: _address(),
            deliveryDate: smIsoDate(_date!),
            gift: _asGift ? _gift : null,
            occasionId: h.occasionId,
            basketId: h.basketId,
            origin: h.origin,
          )
        : smOrderPayload(
            clientRequestId: _keys.keyFor(_scope),
            cart: _c.cart,
            address: _address(),
            origin: _c.cartOrigin,
          );
    try {
      final res = await _c.api.placeOrder(payload);
      _keys.settled(_scope);
      _c.clearCart();
      if (!mounted) return;
      // Сават бўш — тугма барибир ўчиқ қолади (_formOk); айланувчи белги диалог ортида қолмасин.
      setState(() => _submitting = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('sm_order_done'),
          title: Text(ctx.tr('sm_order_placed_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SmSumRow(label: ctx.tr('sm_goods_total'), amount: res.goodsTotal),
              SmSumRow(label: ctx.tr('sm_fee'), amount: res.fee),
              if (res.incentiveApplied > 0)
                SmSumRow(
                    label: ctx.tr('sm_incentive_applied'),
                    amount: res.incentiveApplied,
                    valueKey: const ValueKey('sm_incentive_applied')),
              SmSumRow(label: ctx.tr('sm_hold_total'), amount: res.hold, bold: true),
              const SizedBox(height: 8),
              Text(ctx.tr('sm_order_placed_body'), style: const TextStyle(fontSize: 15)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('sm_ok'))),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.settings.name == kSmHomeRouteName || r.isFirst);
    } on SmCallError catch (e) {
      // Тармоқ/вақт хатоси — натижа номаълум: калит САҚЛАНАДИ (қайта уриниш дубль ясамайди).
      if (e.key != 'sm_err_network') _keys.settled(_scope);
      if (mounted) {
        setState(() {
          _errorKey = e.key;
          _errorMessages = e.messages;
          _serverShort = e.key == 'sm_err_insufficient_funds' ? smServerShortfall(e.details) : 0;
        });
      }
      // Вақт ўтиб кетган / туман ёпилган — янги вақтлар.
      if (e.code == 'SLOT_UNAVAILABLE' || e.code == 'DISTRICT_NOT_SERVED' || e.code == 'MODULE_CLOSED') await _refreshAccess();
    } catch (e) {
      debugPrint('[Supermarket] SUPERMARKET_ORDER_FAILED: $e');
      if (mounted) {
        setState(() {
          _errorKey = 'sm_err_generic';
          _errorMessages = const {};
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editArea() async {
    final picked = await (widget.pickArea?.call(context) ??
        Navigator.of(context).push<GeoArea>(MaterialPageRoute(builder: (_) => const GeoAreaPickScreen())));
    if (picked != null && !picked.isEmpty) {
      setState(() => _c.deliveryArea = picked);
      await _refreshAccess();
    }
  }

  String _errorText(BuildContext context) {
    final server = smServerMessage(_errorMessages, context.contentLang);
    return server.isNotEmpty ? server : context.tr(_errorKey!);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final access = _c.access;
    final t = _c.totals;
    final hasWeighed = t.weighedTotal > 0;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('sm_checkout_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_holiday) ...[
            _Section(title: context.tr('sm_gift_title'), children: [
              SmGiftSection(
                asGift: _asGift,
                onToggle: (v) => setState(() {
                  _asGift = v;
                  _showGiftErrors = false;
                }),
                name: _giftName,
                phone: _giftPhone,
                message: _giftMsg,
                showErrors: _showGiftErrors,
                onChanged: () => setState(() {}),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          _Section(title: context.tr(_holiday && _asGift ? 'sm_gift_address' : 'sm_address'), children: [
            ListTile(
              key: const ValueKey('sm_checkout_district'),
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 12,
              leading: Icon(Icons.place_outlined, color: c.brandText),
              title: Text(
                _c.deliveryArea.label.trim().isEmpty ? context.tr('sm_address_choose') : _c.deliveryArea.label,
                style: const TextStyle(fontSize: 16),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editArea,
            ),
            _Field(controller: _mahalla, label: context.tr('sm_addr_mahalla'), fieldKey: 'mahalla'),
            _Field(controller: _street, label: context.tr('sm_addr_street'), fieldKey: 'street'),
            _Field(controller: _house, label: context.tr('sm_addr_house'), fieldKey: 'house'),
            _Field(controller: _landmark, label: context.tr('sm_addr_landmark'), fieldKey: 'landmark'),
            _Field(
              controller: _phone,
              label: context.tr('sm_addr_phone'),
              fieldKey: 'phone',
              keyboard: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
          ]),
          const SizedBox(height: 12),
          _Section(title: context.tr('sm_delivery_time'), children: [
            if (!access.allowed)
              Text(
                smServerMessage(access.messages, lang).isNotEmpty
                    ? smServerMessage(access.messages, lang)
                    : context.tr('sm_not_available_here'),
                key: const ValueKey('sm_access_denied'),
                style: TextStyle(fontSize: 15, color: c.danger),
              )
            else if (_holiday) ...[
              // Совға/байрам: фақат сана (вақт оралиғи йўқ, эга 2026-11-28).
              if (_dates.isNotEmpty)
                SmDeliveryDatePicker(
                  today: _today,
                  dates: _dates,
                  selected: _date ?? _dates.first,
                  onSelected: (d) => setState(() => _date = d),
                ),
            ] else
              Text(context.tr('sm_delivery_asap'), key: const ValueKey('sm_delivery_asap'), style: const TextStyle(fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final balance = _lastBalance;
              final hold = t.holdEstimate;
              final bonus = _bonusEstimate;
              // Сервер аниқ етишмовчилик айтган бўлса — ўша (бонус кутилгандан кам қўлланган).
              final short = _shortfall > 0 ? _shortfall : _serverShort;
              return _Section(title: context.tr('sm_payment_wallet'), children: [
                if (balance != null)
                  SmSumRow(label: context.tr('sm_wallet_balance'), amount: balance, valueKey: const ValueKey('sm_balance')),
                const Divider(),
                SmSumRow(label: context.tr('sm_goods_total'), amount: t.goodsTotal),
                if (hasWeighed)
                  SmSumRow(
                      label: context.tr('sm_weighed_hold').replaceAll('{p}', '${access.weighHoldPercent}'),
                      amount: t.weighedHold,
                      valueKey: const ValueKey('sm_weighed_hold')),
                SmSumRow(
                  label: context.tr('sm_fee_estimate').replaceAll('{p}', '${access.feePercent}'),
                  amount: t.feeEstimate,
                ),
                SmSumRow(label: context.tr('sm_hold_total'), amount: hold, bold: bonus <= 0, valueKey: const ValueKey('sm_hold')),
                if (bonus > 0) ...[
                  SmSumRow(
                      label: context.tr('sm_incentive_estimate'),
                      amount: bonus,
                      valueKey: const ValueKey('sm_incentive_estimate')),
                  SmSumRow(
                      label: context.tr('sm_after_bonus'),
                      amount: hold - bonus,
                      bold: true,
                      valueKey: const ValueKey('sm_after_bonus')),
                ],
                if (hasWeighed) ...[const SizedBox(height: 8), SmWeighedNote(percent: access.weighHoldPercent)],
                const SizedBox(height: 4),
                Text(context.tr('sm_fee_final_note'), style: TextStyle(fontSize: 13, color: c.ink2)),
                if (short > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('sm_wallet_short').replaceAll('{amount}', formatMoney(short)),
                    key: const ValueKey('sm_wallet_short'),
                    style: TextStyle(fontSize: 15, color: c.danger),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('sm_topup'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => widget.openTopUp != null
                        ? widget.openTopUp!(context, short)
                        : openWalletTopUp(Navigator.of(context), suggestedAmount: short),
                    child: Text(context.tr('sm_topup'), style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ]);
            },
          ),
          if (_errorKey != null) ...[
            const SizedBox(height: 12),
            Text(_errorText(context),
                key: const ValueKey('sm_checkout_error'), style: TextStyle(fontSize: 15, color: c.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('sm_confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _submitting || !_baseOk || _shortfall > 0 ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(context.tr('sm_confirm'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.fieldKey, this.keyboard, this.onChanged});

  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: ValueKey('sm_addr_$fieldKey'),
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}

/// Бонус қоплаши МУМКИН бўлган энг кўп сумма: қолдиқ, товар суммасидан ошмайди (етказиш ҳақи бонусдан эмас —
/// AVA дўкони қоидаси билан бир хил, INFERRED). Якуний қиймат серверда.
int smBonusEstimate({required int incentive, required int goodsTotal}) {
  if (incentive <= 0 || goodsTotal <= 0) return 0;
  return incentive < goodsTotal ? incentive : goodsTotal;
}

/// `INSUFFICIENT_*` хатоси `details` → етишмаган сумма (`required - balance`); номаълум — 0.
int smServerShortfall(Map<String, dynamic> details) {
  final r = details['required'];
  final b = details['balance'];
  if (r is! num || b is! num) return 0;
  final d = r.toInt() - b.toInt();
  return d > 0 ? d : 0;
}

/// AVA бонуси қолдиғи (`users/{uid}.incentiveBalance`, мавжуд [UserRepository.watchWalletBalances]).
/// Телефон йўқ — бўш оқим (бонус ҳисобга олинмайди, хавфсиз томон).
Stream<int> smIncentiveBalanceStream() async* {
  final uid = await walletPhoneId();
  if (uid.isEmpty) return;
  yield* UserRepository().watchWalletBalances(uid).map((b) => b.incentive);
}

/// Слот кўриниши учун ишлатилади (тестларда ҳам).
String smSlotText(SmSlot s, String lang) => s.label(lang);
