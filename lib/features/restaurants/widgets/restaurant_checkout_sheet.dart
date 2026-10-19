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
  });

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

  Restaurant get _r => widget.restaurant;

  @override
  void initState() {
    super.initState();
    _fulfillment = _r.delivery.hasDelivery ? 'delivery' : 'pickup';
    _foodPayment = _defaultFoodPayment();
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
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _utensils > 0 ? () => setState(() => _utensils--) : null,
                ),
                Text(
                  _utensils == 0 ? context.tr('restaurants_utensils_none') : '$_utensils',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? c.brand : c.ink3,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: c.ink)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, style: TextStyle(fontSize: 11, color: c.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
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
