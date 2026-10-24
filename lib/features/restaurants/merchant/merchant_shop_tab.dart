// Ресторан панели — «Дўкон» (§12.8, 店铺装修): логотип/муқова, эълон,
// профил (форма — умумий), реквизит (`private/payment`), пауза.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import '../services/restaurant_storage_service.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'restaurant_form_fields.dart';
import 'restaurant_register_form.dart';
import 'restaurant_video_card.dart';

class MerchantShopTab extends StatefulWidget {
  const MerchantShopTab({super.key, required this.restaurant, required this.repository, this.storage});

  final Restaurant restaurant;
  final RestaurantsRepository repository;
  final RestaurantStorageService? storage;

  @override
  State<MerchantShopTab> createState() => _MerchantShopTabState();
}

class _MerchantShopTabState extends State<MerchantShopTab> {
  late final RestaurantStorageService _storage = widget.storage ?? RestaurantStorageService();
  late final RestaurantFormData _data = _fromRestaurant(widget.restaurant);
  late final _announcement = TextEditingController(text: widget.restaurant.announcement);
  final _card = TextEditingController();
  final _holder = TextEditingController();
  bool _paymentLoaded = false;
  bool _dirty = false;
  bool _saving = false;
  bool _uploading = false;

  Restaurant get _r => widget.restaurant;

  static RestaurantFormData _fromRestaurant(Restaurant r) => RestaurantFormData(
        name: r.name,
        legalType: r.legalType,
        description: r.description,
        cuisineTags: r.cuisineTags,
        address: r.address,
        contactPhone: r.contactPhone,
        lat: r.lat,
        lng: r.lng,
        deliveryMode: r.delivery.mode,
        pickup: r.delivery.pickup,
        ownFeeType: r.delivery.ownFee.type,
        ownFeeFixed: r.delivery.ownFee.fixed,
        ownFeeBase: r.delivery.ownFee.base,
        ownFeePerKm: r.delivery.ownFee.perKm,
        ownFeeFreeAbove: r.delivery.ownFee.freeAbove,
        ownFeeMaxKm: r.delivery.ownFee.maxKm,
        prepay: r.payment.prepay,
        cash: r.payment.cash,
        prepTimeMin: r.prepTimeMin,
        minOrderAmount: r.minOrderAmount,
        maxQtyPerItem: r.maxQtyPerItem,
        acceptsPreorder: r.acceptsPreorder,
        acceptsBookings: r.acceptsBookings,
        bookingSeats: r.bookingSeats,
        bookingNote: r.bookingNote,
        alwaysOpen: r.openingHours == null,
        openTime: r.openingHours?.open ?? '09:00',
        closeTime: r.openingHours?.close ?? '22:00',
      );

  @override
  void initState() {
    super.initState();
    widget.repository.watchPaymentDetails(_r.id).first.then((p) {
      if (!mounted) return;
      setState(() {
        _card.text = (p?['cardNumber'] ?? '') as String;
        _holder.text = (p?['cardHolder'] ?? '') as String;
        _paymentLoaded = true;
      });
    }).catchError((_) {
      if (mounted) setState(() => _paymentLoaded = true);
    });
  }

  @override
  void dispose() {
    _announcement.dispose();
    _card.dispose();
    _holder.dispose();
    super.dispose();
  }

  /// Матн `mounted` текширувидан КЕЙИН ҳосил қилинади (context async
  /// бўшлиқдан кейин ишлатилмайди).
  void _snack({String? key, Object? error, bool isError = false}) {
    if (!mounted) return;
    final text = error != null ? restaurantsErrorText(context, error) : context.tr(key ?? 'restaurants_err_generic');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error != null || isError ? Colors.red.shade700 : null),
    );
  }

  Future<void> _uploadImage(String kind) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _storage.uploadImage(restaurantId: _r.id, image: f, kind: kind);
      await widget.repository.updateProfile(_r.id, {kind == 'logo' ? 'logoUrl' : 'coverUrl': url});
      _snack(key: 'restaurants_m_saved');
    } catch (e) {
      _snack(error: e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveProfile() async {
    final errs = _data.validate();
    if (errs.isNotEmpty) {
      _snack(key: 'restaurants_m_err_${errs.first}', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProfile(_r.id, {
        ..._data.toProfilePatch(),
        'announcement': _announcement.text.trim(),
      });
      final card = _card.text.replaceAll(RegExp(r'\D'), '');
      if (_paymentLoaded && (card.isNotEmpty || _holder.text.trim().isNotEmpty)) {
        if (card.length != 16) {
          _snack(key: 'restaurants_m_err_card_number', isError: true);
        } else {
          await widget.repository.savePaymentDetails(_r.id, cardNumber: card, cardHolder: _holder.text.trim());
        }
      }
      setState(() => _dirty = false);
      _snack(key: 'restaurants_m_saved');
    } catch (e) {
      _snack(error: e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pause(Duration? d, {bool untilEndOfDay = false}) async {
    DateTime? until;
    final now = DateTime.now();
    if (untilEndOfDay) {
      until = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (d != null) {
      until = now.add(d);
    }
    try {
      await widget.repository.setPaused(_r.id, until);
    } catch (e) {
      _snack(error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final paused = _r.isPausedAt(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            _ImageSlot(label: context.tr('restaurants_m_logo'), url: _r.logoUrl, size: 84, onTap: _uploading ? null : () => _uploadImage('logo')),
            const SizedBox(width: 12),
            Expanded(
              child: _ImageSlot(label: context.tr('restaurants_m_cover'), url: _r.coverUrl, size: 84, wide: true, onTap: _uploading ? null : () => _uploadImage('cover')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        RestaurantVideoCard(
          restaurantId: _r.id,
          ownerPhone: _r.ownerUid,
          restaurantApproved: _r.status == 'approved',
        ),
        const SizedBox(height: 12),
        Text(context.tr('restaurants_m_pause'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (paused)
              FilledButton.tonal(onPressed: () => _pause(null), child: Text(context.tr('restaurants_m_resume')))
            else ...[
              OutlinedButton(onPressed: () => _pause(const Duration(minutes: 30)), child: Text(context.tr('restaurants_m_pause_30'))),
              OutlinedButton(onPressed: () => _pause(null, untilEndOfDay: true), child: Text(context.tr('restaurants_m_pause_today'))),
              OutlinedButton(onPressed: () => _pause(const Duration(days: 365)), child: Text(context.tr('restaurants_m_pause_manual'))),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _announcement,
          maxLength: 120,
          decoration: InputDecoration(labelText: context.tr('restaurants_m_announcement'), border: const OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        RestaurantFormFields(
          data: _data,
          showLegalType: false,
          showPaymentDetails: false,
          showMaxQty: true,
          bookingsDisabled: _r.bookingsDisabled,
          onChanged: () => setState(() => _dirty = true),
        ),
        const SizedBox(height: 16),
        Text(context.tr('restaurants_m_payment_details'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 6),
        TextField(
          controller: _card,
          enabled: _paymentLoaded,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
          decoration: InputDecoration(labelText: context.tr('restaurants_m_card_number'), border: const OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _holder,
          enabled: _paymentLoaded,
          maxLength: 60,
          decoration: InputDecoration(labelText: context.tr('restaurants_m_card_holder'), border: const OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving || !_dirty ? null : _saveProfile,
          style: FilledButton.styleFrom(
            backgroundColor: c.brand,
            foregroundColor: c.brandInk,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('restaurants_m_save'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.label, required this.url, required this.size, required this.onTap, this.wide = false});

  final String label;
  final String url;
  final double size;
  final bool wide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final has = url.trim().startsWith('http');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: wide ? double.infinity : size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              has ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover) : ColoredBox(color: c.surface2),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
