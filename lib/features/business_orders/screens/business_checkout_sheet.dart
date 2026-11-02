// «Менинг бизнесим» буюртмасини расмийлаштириш варағи: сават қаторлари · манзил · изоҳ · маҳсулот пули (эшик
// олдида курьерга нақд) · етказиш ҳақи (нақд / ҳамён) · ҳисоб · «Буюртма бериш».
//
// Нарх ва етказиш ҳақи — фақат сервердан (`quoteBusinessOrder`, `placeBusinessOrder`); бу ерда кўрсатилади.
// Идемпотентлик (21-қоида): ҳар «ният» (объект + сават + манзил + тўлов + изоҳ) учун калит БИР МАРТА ясалади
// ([IdempotencyKeys]); жавоб йўқолиб қайта босилса — ўша калит, сервер иккинчи буюртма очмайди.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../models/user_address.dart';
import '../../../repositories/user_repository.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../data/business_order_session.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../widgets/business_order_widgets.dart';
import 'business_order_screen.dart';

/// Харидор маълумоти (телефон, исм, манзил, ҳамён қолдиғи).
typedef BizCheckoutProfile = ({String phone, String name, UserAddress? address, int walletBalance});

Future<void> showBusinessCheckoutSheet(
  BuildContext context, {
  required BusinessCart cart,
  BusinessOrdersRepository? repository,
  BusinessCartStore? store,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.ava.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: BusinessCheckoutSheet(cart: cart, repository: repository, store: store),
    ),
  );
}

class BusinessCheckoutSheet extends StatefulWidget {
  const BusinessCheckoutSheet({
    super.key,
    required this.cart,
    this.repository,
    this.store,
    @visibleForTesting this.loadProfile,
    @visibleForTesting this.editAddress,
    @visibleForTesting this.keys,
    @visibleForTesting this.onPlaced,
  });

  final BusinessCart cart;
  final BusinessOrdersRepository? repository;
  final BusinessCartStore? store;

  /// Тест учун: харидор маълумоти (бўлмаса — SharedPreferences + `UserRepository`).
  final Future<BizCheckoutProfile> Function()? loadProfile;

  /// Тест учун: манзилни таҳрирлаш (бўлмаса — мавжуд [AddressEditScreen], харита + GPS).
  final Future<UserAddress?> Function(BuildContext context, UserAddress? current)? editAddress;

  /// Тест учун: идемпотентлик калитлари (генератор алмаштирилади).
  final IdempotencyKeys? keys;

  /// Тест учун: муваффақиятдан кейин (бўлмаса — варақ ёпилиб буюртма экрани очилади).
  final void Function(BuildContext context, BusinessPlaceResult result)? onPlaced;

  @override
  State<BusinessCheckoutSheet> createState() => _BusinessCheckoutSheetState();
}

class _BusinessCheckoutSheetState extends State<BusinessCheckoutSheet> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  late final BusinessCartStore _store = widget.store ?? BusinessCartStore.instance;
  late final IdempotencyKeys _keys = widget.keys ?? IdempotencyKeys(generator: () => 'biz_${newRequestId()}');
  final _noteCtrl = TextEditingController();

  String _name = '';
  UserAddress? _address;
  int _walletBalance = 0;
  String _deliveryPayment = 'cash';
  List<String> _deliveryMethods = const ['cash', 'wallet'];

  BusinessOrderQuote? _quote;
  bool _quoting = false;
  String? _quoteError;
  int _quoteSeq = 0;
  bool _sending = false;

  BusinessCart get _cart => widget.cart;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<BizCheckoutProfile> _defaultProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    var name = prefs.getString('user_name') ?? '';
    UserAddress? address;
    var balance = 0;
    if (phone.length >= 9 && mounted) {
      final user = await context.read<UserRepository>().getById(phone);
      address = user?.address;
      balance = user?.bonusBalance ?? 0;
      if (name.isEmpty) name = user?.name ?? '';
    }
    return (phone: phone, name: name, address: address, walletBalance: balance);
  }

  Future<void> _load() async {
    try {
      final p = await (widget.loadProfile?.call() ?? _defaultProfile());
      if (!mounted) return;
      setState(() {
        _name = p.name;
        _address = p.address;
        _walletBalance = p.walletBalance;
      });
    } catch (e) {
      debugPrint('[BizCheckout] profile: $e');
    }
    await _requote();
  }

  (double, double)? get _coords {
    final a = _address;
    if (a != null && a.lat != null && a.lng != null) return (a.lat!, a.lng!);
    return null;
  }

  Future<void> _requote() async {
    final co = _coords;
    final seq = ++_quoteSeq;
    if (co == null || _cart.isEmpty) {
      setState(() {
        _quote = null;
        _quoteError = null;
        _quoting = false;
      });
      return;
    }
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final q = await _repo.quote(businessId: _cart.businessId, items: _cart.toItems(), lat: co.$1, lng: co.$2);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = q;
        if (q.deliveryPaymentMethods.isNotEmpty) {
          _deliveryMethods = q.deliveryPaymentMethods;
          if (!_deliveryMethods.contains(_deliveryPayment)) _deliveryPayment = _deliveryMethods.first;
        }
      });
    } catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = null;
        _quoteError = bizOrderErrorText(context, e);
      });
    } finally {
      if (mounted && seq == _quoteSeq) setState(() => _quoting = false);
    }
  }

  Future<void> _editAddress() async {
    final custom = widget.editAddress;
    final current = _address;
    final Future<UserAddress?> pending = custom != null
        ? custom(context, current)
        : Navigator.of(context).push<UserAddress>(
            MaterialPageRoute(builder: (_) => AddressEditScreen(initial: current)),
          );
    final next = await pending;
    if (!mounted || next == null) return;
    setState(() => _address = next);
    await _requote();
  }

  void _setQty(BusinessCartLine l, int qty) {
    setState(() => _cart.setQty(l.itemId, qty));
    _store.changed();
    _requote();
  }

  String get _scope {
    final co = _coords;
    return [
      _cart.businessId,
      _cart.signature,
      co == null ? '' : '${co.$1},${co.$2}',
      _deliveryPayment,
      _noteCtrl.text.trim(),
    ].join('|');
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.ava.danger, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _place() async {
    final co = _coords;
    if (_cart.isEmpty || _sending) return;
    if (co == null) {
      _showError(context.tr('biz_order_err_address_required'));
      return;
    }
    final scope = _scope;
    final key = _keys.keyFor(scope);
    setState(() => _sending = true);
    try {
      final res = await _repo.place(
        idempotencyKey: key,
        businessId: _cart.businessId,
        items: _cart.toItems(),
        lat: co.$1,
        lng: co.$2,
        address: _address?.formatted ?? '',
        note: _noteCtrl.text.trim(),
        userName: _name,
        deliveryPaymentMethod: _deliveryPayment,
      );
      _keys.settled(scope);
      if (!mounted) return;
      _store.clear(_cart.businessId);
      _cart.clear();
      final custom = widget.onPlaced;
      if (custom != null) return custom(context, res);
      final nav = Navigator.of(context, rootNavigator: true);
      final messenger = ScaffoldMessenger.of(nav.context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(context.tr('biz_order_placed_ok'))));
      await nav.push(MaterialPageRoute<void>(
        builder: (_) => BusinessOrderScreen(orderId: res.orderId, repository: _repo),
      ));
    } catch (e) {
      // Калит САҚЛАНАДИ (тармоқ/вақт хатосида қайта босиш — ўша буюртма). Фақат калит зиддиятида — янги калит.
      if (e is BusinessOrderException && e.reason == 'IDEMPOTENCY_KEY_CONFLICT') _keys.settled(scope);
      if (!mounted) return;
      _showError(bizOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final q = _quote;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final canSend = !_sending && _cart.isNotEmpty && _coords != null && q != null && !_quoting;
    final itemsTotal = q?.itemsTotal ?? _cart.itemsTotal;
    final fee = q?.deliveryFee ?? 0;
    final cashAtDoor = itemsTotal + (_deliveryPayment == 'cash' ? fee : 0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 0, AvaSpace.screen, AvaSpace.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('biz_order_checkout_title'), style: AvaText.sectionTitle.copyWith(color: c.ink)),
            if (_cart.businessName.isNotEmpty)
              Text(_cart.businessName, style: TextStyle(fontSize: 13, color: c.ink2)),
            const SizedBox(height: 10),

            // 1. Сават
            if (_cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(context.tr('biz_order_cart_empty'), style: TextStyle(color: c.ink2)),
              ),
            for (final l in _cart.lines) _CartRow(line: l, onQty: (n) => _setQty(l, n)),
            const SizedBox(height: 8),

            // 2. Манзил
            Text(context.tr('biz_order_address'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            _AddressCard(address: _address, hasCoords: _coords != null, onEdit: _editAddress),
            const SizedBox(height: 10),

            // 3. Изоҳ
            TextField(
              key: const ValueKey('biz_checkout_note'),
              controller: _noteCtrl,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: context.tr('biz_order_note_hint'),
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // 4. Маҳсулот пули — эшик олдида курьерга нақд (ягона усул: `cash_buyout`).
            Text(context.tr('biz_order_goods_payment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            BizOrderNotice(
              key: const ValueKey('biz_checkout_goods_explain'),
              icon: Icons.payments_outlined,
              text: context.tr('biz_order_goods_cash_explain'),
              color: c.brandText,
              background: c.brandSoft,
            ),
            const SizedBox(height: 12),

            // 5. Етказиш ҳақи
            Text(context.tr('biz_order_delivery_payment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            if (_deliveryMethods.contains('cash'))
              _RadioRow(
                key: const ValueKey('biz_checkout_pay_cash'),
                selected: _deliveryPayment == 'cash',
                title: context.tr('biz_order_delivery_cash'),
                onTap: () => setState(() => _deliveryPayment = 'cash'),
              ),
            if (_deliveryMethods.contains('wallet'))
              _RadioRow(
                key: const ValueKey('biz_checkout_pay_wallet'),
                selected: _deliveryPayment == 'wallet',
                title: context.tr('biz_order_delivery_wallet'),
                subtitle:
                    '${context.tr('biz_order_wallet_balance').replaceAll('{amount}', formatMoney(_walletBalance))} · ${context.tr('biz_order_wallet_note')}',
                onTap: () => setState(() => _deliveryPayment = 'wallet'),
              ),
            Divider(color: c.line),

            // 6. Ҳисоб (сервер квотаси)
            BizOrderMoneyLine(label: context.tr('biz_order_items_total'), amount: itemsTotal),
            BizOrderMoneyLine(
              key: const ValueKey('biz_checkout_fee'),
              label: context.tr('biz_order_delivery_fee'),
              amount: fee,
              valueText: _quoting
                  ? context.tr('biz_order_quoting')
                  : (q == null ? (_quoteError ?? context.tr('biz_order_address_needed')) : null),
            ),
            if (q != null && !_quoting) ...[
              BizOrderMoneyLine(
                key: const ValueKey('biz_checkout_total'),
                label: context.tr('biz_order_total'),
                amount: q.total,
                bold: true,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('biz_order_pay_at_door').replaceAll('{amount}', formatMoney(cashAtDoor)),
                key: const ValueKey('biz_checkout_cash_at_door'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.brandText),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('biz_checkout_place'),
              onPressed: canSend ? _place : null,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('biz_order_cta'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.onQty});

  final BusinessCartLine line;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final l = line;
    return Padding(
      key: ValueKey('biz_cart_row_${l.itemId}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                Text(formatMoney(l.lineTotal), style: TextStyle(fontSize: 12, color: c.ink2)),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('biz_cart_minus_${l.itemId}'),
            tooltip: context.tr(l.qty <= 1 ? 'biz_order_remove' : 'biz_order_qty_less'),
            icon: Icon(l.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_circle_outline_rounded),
            onPressed: () => onQty(l.qty - 1),
          ),
          Text(bizOrderQtyLabel(context, l.qty, l.priceUnit), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          IconButton(
            key: ValueKey('biz_cart_plus_${l.itemId}'),
            tooltip: context.tr('biz_order_qty_more'),
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: l.qty >= BusinessOrderLimits.maxQtyPerItem ? null : () => onQty(l.qty + 1),
          ),
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({super.key, required this.selected, required this.title, required this.onTap, this.subtitle});

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AvaTap.minSize),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 20,
                    color: selected ? c.brandText : c.ink2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, color: c.ink)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!, style: TextStyle(fontSize: 12, color: c.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.hasCoords, required this.onEdit});

  final UserAddress? address;
  final bool hasCoords;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final a = address;
    final ok = a != null && hasCoords;
    return InkWell(
      key: const ValueKey('biz_checkout_address'),
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: AvaTap.minSize),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: ok ? c.surface2 : c.warnSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ok ? c.line : c.warn),
        ),
        child: Row(
          children: [
            Icon(Icons.place_outlined, size: 18, color: ok ? c.ink2 : c.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok && a.formatted.isNotEmpty ? a.formatted : context.tr('biz_order_address_needed'),
                style: TextStyle(fontSize: 13, color: ok ? c.ink : c.warn),
              ),
            ),
            const SizedBox(width: 6),
            Text(context.tr('biz_order_address_change'), style: TextStyle(fontSize: 12, color: c.brandText)),
          ],
        ),
      ),
    );
  }
}
