// Буюртма бериш варағи (§12.5): манзил · етказиш/олиб кетиш · идиш-товоқ ·
// изоҳ · таом пули усули · етказиш пули усули · ҳисоб · «Буюртма бериш».
//
// Нарх ва етказиш ҳақи — сервердан (`quoteRestaurantDelivery`,
// `placeRestaurantOrder`); бу ерда фақат кўрсатилади. Idempotency калити
// варақ очилганда БИР МАРТА (такрор босиш → ўша буюртма).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/user_address.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';
import '../../profile/screens/address_edit_screen.dart';
import '../data/restaurants_repository.dart';
import '../domain/preorder.dart';
import '../domain/restaurant_models.dart';
import '../screens/restaurant_order_screen.dart';

/// Сервер хатоси → фойдаланувчи матни; калит йўқ бўлса умумий матн.
String restaurantsErrorText(BuildContext context, Object e) {
  if (e is RestaurantsException) {
    final k = e.l10nKey;
    final s = context.tr(k);
    if (s != k) return s;
  }
  return context.tr('restaurants_err_generic');
}

Future<void> showRestaurantCheckoutSheet(
  BuildContext context, {
  required Restaurant restaurant,
  required RestaurantCart cart,
  required RestaurantsRepository repository,
  double? userLat,
  double? userLng,
}) {
  final c = context.ava;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: c.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: RestaurantCheckoutSheet(
        restaurant: restaurant,
        cart: cart,
        repository: repository,
        userLat: userLat,
        userLng: userLng,
      ),
    ),
  );
}

class RestaurantCheckoutSheet extends StatefulWidget {
  const RestaurantCheckoutSheet({
    super.key,
    required this.restaurant,
    required this.cart,
    required this.repository,
    this.userLat,
    this.userLng,
    this.now,
  });

  /// Тест учун соат; бўш бўлса ҳақиқий вақт.
  final DateTime Function()? now;

  final Restaurant restaurant;
  final RestaurantCart cart;
  final RestaurantsRepository repository;
  final double? userLat;
  final double? userLng;

  @override
  State<RestaurantCheckoutSheet> createState() => _RestaurantCheckoutSheetState();
}

class _RestaurantCheckoutSheetState extends State<RestaurantCheckoutSheet> {
  final _idempotencyKey = 'rest_${const Uuid().v4().replaceAll('-', '')}';
  final _noteCtrl = TextEditingController();

  String _phone = '';
  String _name = '';
  UserModel? _profile;
  UserAddress? _address;
  int _walletBalance = 0;

  late String _fulfillment; // delivery | pickup
  late String _foodPayment; // prepay | cash_buyout | cash_to_restaurant
  String _deliveryPayment = 'cash'; // cash | wallet
  int _utensils = 0;

  DeliveryQuote? _quote;
  bool _quoting = false;
  String? _quoteError;
  bool _sending = false;

  // Олдиндан буюртма (S4b, D-REST-35): «ҳозир» ёки танланган кун ва вақт.
  bool _preorder = false;
  late DateTime _scheduled;

  Restaurant get _r => widget.restaurant;

  DateTime get _now => (widget.now ?? DateTime.now)();

  /// Ресторан ҳозир ёпиқ, лекин олдиндан буюртма олади — «ҳозир» танлови йўқ.
  bool get _mustPreorder => _r.acceptsPreorder && !_r.isOpenAt(_now);

  /// Танланган вақтнинг хатоси ([Preorder] қоидаси; сервер барибир текширади) — «ҳозир»да `null`.
  String? get _preorderError =>
      _preorder ? Preorder.check(now: _now, scheduled: _scheduled, restaurant: _r) : null;

  @override
  void initState() {
    super.initState();
    _fulfillment = _r.delivery.hasDelivery ? 'delivery' : 'pickup';
    _foodPayment = _defaultFoodPayment();
    _scheduled = Preorder.suggest(_now);
    _preorder = _mustPreorder;
    _loadProfile();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _deliveryMode => _fulfillment == 'pickup' ? 'pickup' : _r.delivery.mode;

  /// Рухсат этилган таом пули усуллари — рестораннинг режими ва созламаси.
  List<String> get _foodPaymentOptions {
    final out = <String>[];
    if (_r.payment.prepay) out.add('prepay');
    if (_r.payment.cash) {
      out.add(_deliveryMode == 'ava_courier' ? 'cash_buyout' : 'cash_to_restaurant');
    }
    return out;
  }

  String _defaultFoodPayment() {
    final o = _foodPaymentOptions;
    return o.isEmpty ? 'prepay' : o.first;
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _phone = phoneDigits(prefs.getString('user_phone') ?? '');
      _name = prefs.getString('user_name') ?? '';
      if (_phone.length >= 9 && mounted) {
        final user = await context.read<UserRepository>().getById(_phone);
        if (!mounted) return;
        setState(() {
          _profile = user;
          _address = user?.address;
          _walletBalance = user?.bonusBalance ?? 0;
          if (_name.isEmpty) _name = user?.name ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() {});
    await _requote();
  }

  (double, double)? get _coords {
    final a = _address;
    if (a != null && a.lat != null && a.lng != null) return (a.lat!, a.lng!);
    if (widget.userLat != null && widget.userLng != null) return (widget.userLat!, widget.userLng!);
    return null;
  }

  Future<void> _requote() async {
    if (_fulfillment == 'pickup') {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
      return;
    }
    final co = _coords;
    if (co == null) {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
      return;
    }
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final q = await widget.repository.quoteDelivery(
        restaurantId: _r.id,
        lat: co.$1,
        lng: co.$2,
        itemsTotal: widget.cart.itemsTotal,
        scheduledFor: _preorder ? _scheduled : null,
      );
      if (!mounted) return;
      setState(() => _quote = q);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteError = restaurantsErrorText(context, e);
      });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _editAddress() async {
    final userRepo = context.read<UserRepository>();
    final filled = await AddressGate.ensureFilled(context, user: _profile, current: null);
    if (!mounted) return;
    if (filled != null) {
      setState(() => _address = filled);
    } else if (_phone.length >= 9) {
      // Манзил бошқа оқимда сақланган бўлиши мумкин — қайта ўқиймиз.
      final user = await userRepo.getById(_phone);
      if (!mounted) return;
      setState(() {
        _profile = user;
        _address = user?.address;
      });
    }
    await _requote();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _place() async {
    final cart = widget.cart;
    if (cart.isEmpty) return;
    final delivery = _fulfillment == 'delivery';
    final co = _coords;
    if (delivery && co == null) {
      _showError(context.tr('restaurants_err_DELIVERY_ADDRESS_REQUIRED'));
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await widget.repository.placeOrder(
        idempotencyKey: _idempotencyKey,
        restaurantId: _r.id,
        items: cart.toOrderItems(),
        fulfillmentMode: _fulfillment,
        foodPaymentMethod: _foodPayment,
        deliveryPaymentMethod: _deliveryMode == 'ava_courier' ? _deliveryPayment : 'none',
        address: delivery ? (_address?.formatted ?? '') : '',
        lat: delivery ? co!.$1 : null,
        lng: delivery ? co!.$2 : null,
        note: _noteCtrl.text.trim(),
        utensils: _utensils,
        userName: _name,
        scheduledFor: _preorder ? _scheduled : null,
      );
      if (!mounted) return;
      cart.clear();
      final nav = Navigator.of(context, rootNavigator: true);
      Navigator.of(context).pop();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => RestaurantOrderScreen(orderId: res.orderId, repository: widget.repository),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(restaurantsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final cart = widget.cart;
    final delivery = _fulfillment == 'delivery';
    final fee = delivery ? (_quote?.deliveryFee ?? 0) : 0;
    final total = cart.itemsTotal + fee;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final canSend = !_sending &&
        cart.isNotEmpty &&
        _preorderError == null &&
        (!delivery || (_coords != null && _quote != null && !_quoting));

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('restaurants_checkout_title'), style: AvaText.sectionTitle.copyWith(color: c.ink)),
            const SizedBox(height: 10),

            // 0. Қачон: ҳозир / олдиндан (S4b) — фақат олдиндан буюртма оладиган ресторанда.
            if (_r.acceptsPreorder) ...[
              _WhenBlock(
                preorder: _preorder,
                forced: _mustPreorder,
                scheduled: _scheduled,
                now: _now,
                error: _preorderError,
                onMode: (v) {
                  setState(() => _preorder = v);
                  _requote();
                },
                onChanged: (d) {
                  setState(() => _scheduled = d);
                  _requote();
                },
              ),
              const SizedBox(height: 10),
            ],

            // 1. Етказиш / олиб кетиш
            if (_r.delivery.hasDelivery && _r.delivery.pickup)
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'delivery', label: Text(context.tr('restaurants_mode_delivery'))),
                  ButtonSegment(value: 'pickup', label: Text(context.tr('restaurants_mode_pickup'))),
                ],
                selected: {_fulfillment},
                onSelectionChanged: (s) {
                  setState(() {
                    _fulfillment = s.first;
                    if (!_foodPaymentOptions.contains(_foodPayment)) _foodPayment = _defaultFoodPayment();
                  });
                  _requote();
                },
              )
            else
              _Label(
                icon: delivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                text: context.tr(delivery ? 'restaurants_mode_delivery' : 'restaurants_mode_pickup'),
              ),
            const SizedBox(height: 10),

            // 2. Манзил
            if (delivery)
              _AddressCard(
                address: _address,
                hasCoords: _coords != null,
                onEdit: _editAddress,
              )
            else
              _Label(icon: Icons.place_outlined, text: _r.address.isEmpty ? _r.name : _r.address),
            const SizedBox(height: 10),

            // 3. Идиш-товоқ
            Row(
              children: [
                Expanded(child: Text(context.tr('restaurants_utensils'), style: TextStyle(fontSize: 13, color: c.ink))),
                IconButton(
                  tooltip: context.tr('restaurants_a11y_utensils_less'),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _utensils > 0 ? () => setState(() => _utensils--) : null,
                ),
                // Катта шрифт ва тор экранда матн қирқилади (сатр синмайди).
                Flexible(
                  child: Text(
                    _utensils == 0 ? context.tr('restaurants_utensils_none') : '$_utensils',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('restaurants_a11y_utensils_more'),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _utensils < 10 ? () => setState(() => _utensils++) : null,
                ),
              ],
            ),

            // 4. Изоҳ
            TextField(
              controller: _noteCtrl,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: context.tr('restaurants_note_hint'),
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
              ),
            ),
            const SizedBox(height: 12),

            // 5. Таом пули
            Text(context.tr('restaurants_food_payment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            for (final o in _foodPaymentOptions)
              _RadioRow(
                selected: _foodPayment == o,
                title: context.tr('restaurants_food_payment_$o'),
                subtitle: context.tr('restaurants_food_payment_${o}_hint'),
                onTap: () => setState(() => _foodPayment = o),
              ),

            // 6. Етказиш пули (фақат AVA курьери)
            if (delivery && _deliveryMode == 'ava_courier') ...[
              const SizedBox(height: 6),
              Text(context.tr('restaurants_delivery_payment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
              _RadioRow(
                selected: _deliveryPayment == 'cash',
                title: context.tr('restaurants_delivery_payment_cash'),
                onTap: () => setState(() => _deliveryPayment = 'cash'),
              ),
              _RadioRow(
                selected: _deliveryPayment == 'wallet',
                title: context.tr('restaurants_delivery_payment_wallet'),
                subtitle: context.tr('restaurants_wallet_balance').replaceAll('{amount}', formatPrice(_walletBalance)),
                onTap: () => setState(() => _deliveryPayment = 'wallet'),
              ),
            ],
            const SizedBox(height: 8),
            Divider(color: c.line),

            // 7. Ҳисоб
            _Line(label: context.tr('restaurants_items_total'), value: formatPrice(cart.itemsTotal)),
            if (cart.qtyDiscountTotal > 0)
              _Line(label: context.tr('restaurants_qty_discount'), value: formatPrice(-cart.qtyDiscountTotal)),
            if (delivery)
              _Line(
                label: context.tr('restaurants_delivery_fee'),
                value: _quoting
                    ? '…'
                    : (_quote != null
                        ? (fee == 0 ? context.tr('restaurants_free') : formatPrice(fee))
                        : (_quoteError ?? context.tr('restaurants_address_needed'))),
                warn: _quote == null && !_quoting,
              ),
            _Line(label: context.tr('restaurants_total'), value: formatPrice(total), bold: true),
            const SizedBox(height: 12),

            FilledButton(
              onPressed: canSend ? _place : null,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('restaurants_place_order'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Оддий radio қатори (`RadioListTile` нинг `groupValue` API'си эскирган).
class _RadioRow extends StatelessWidget {
  const _RadioRow({required this.selected, required this.title, required this.onTap, this.subtitle});

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // Radio: guruh ichida yagona tanlov sifatida e'lon qilinadi (TalkBack: «tanlangan/tanlanmagan»),
    // bosish maydoni >= 44 px, ikonka rangi oq fonda 3:1 dan yuqori (brandText / ink2).
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                      Text(title, style: TextStyle(fontSize: 13, color: c.ink)),
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

String _two(int n) => n.toString().padLeft(2, '0');

/// «Қачон?» блоки (S4b): ҳозир / олдиндан; олдиндан — кун чиплари + вақт; хато аниқ ёзилади.
class _WhenBlock extends StatelessWidget {
  const _WhenBlock({
    required this.preorder,
    required this.forced,
    required this.scheduled,
    required this.now,
    required this.error,
    required this.onMode,
    required this.onChanged,
  });

  final bool preorder;

  /// Ресторан ҳозир ёпиқ — фақат олдиндан.
  final bool forced;
  final DateTime scheduled;
  final DateTime now;
  final String? error;
  final ValueChanged<bool> onMode;
  final ValueChanged<DateTime> onChanged;

  String _dayLabel(BuildContext context, DateTime d) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return context.tr('restaurants_preorder_today');
    if (diff == 1) return context.tr('restaurants_preorder_tomorrow');
    return '${_two(d.day)}.${_two(d.month)}';
  }

  Future<void> _pickTime(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: scheduled.hour, minute: scheduled.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) onChanged(Preorder.combine(scheduled, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      key: const ValueKey('when-block'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('restaurants_preorder_when'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 6),
        if (forced)
          Container(
            key: const ValueKey('preorder-forced'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(Icons.nightlight_round, size: 18, color: c.warn),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tr('restaurants_preorder_closed_now'), style: TextStyle(fontSize: 12, color: c.ink))),
              ],
            ),
          )
        else
          SegmentedButton<bool>(
            key: const ValueKey('preorder-mode'),
            segments: [
              ButtonSegment(value: false, label: Text(context.tr('restaurants_preorder_now'))),
              ButtonSegment(value: true, label: Text(context.tr('restaurants_preorder_later'))),
            ],
            selected: {preorder},
            onSelectionChanged: (s) => onMode(s.first),
          ),
        if (preorder) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              key: const ValueKey('preorder-days'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in Preorder.days(now)) ...[
                  ChoiceChip(
                    key: ValueKey('preorder-day-${d.year}-${d.month}-${d.day}'),
                    label: Text(_dayLabel(context, d)),
                    selected: d.year == scheduled.year && d.month == scheduled.month && d.day == scheduled.day,
                    onSelected: (_) => onChanged(Preorder.combine(d, scheduled.hour, scheduled.minute)),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('preorder-time'),
            onPressed: () => _pickTime(context),
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text('${_two(scheduled.hour)}:${_two(scheduled.minute)}'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr('restaurants_preorder_err_$error').replaceAll('{min}', '${Preorder.minLeadMin}').replaceAll('{days}', '${Preorder.maxDays}'),
                key: const ValueKey('preorder-error'),
                style: TextStyle(fontSize: 12, color: c.danger),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context
                    .tr('restaurants_preorder_summary')
                    .replaceAll('{day}', _dayLabel(context, scheduled))
                    .replaceAll('{time}', '${_two(scheduled.hour)}:${_two(scheduled.minute)}'),
                key: const ValueKey('preorder-summary'),
                style: TextStyle(fontSize: 12, color: c.ink2),
              ),
            ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Row(
      children: [
        Icon(icon, size: 18, color: c.ink2),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.ink))),
      ],
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
    final ok = a != null && a.isComplete && hasCoords;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: Container(
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
                ok ? a.formatted : context.tr('restaurants_address_needed'),
                style: TextStyle(fontSize: 13, color: ok ? c.ink : c.warn),
              ),
            ),
            Text(context.tr('restaurants_address_change'), style: TextStyle(fontSize: 12, color: c.brandText)),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false, this.warn = false});

  final String label;
  final String value;
  final bool bold;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final style = TextStyle(
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: warn ? c.warn : c.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}
