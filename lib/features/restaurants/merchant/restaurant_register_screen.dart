// Рўйхатдан ўтиш (Б2.1, D-REST-7): форма → «Тасдиқлайман» → `restaurantRegister` → `approved`
// (эга, 2026-10-31: ариза занжири йўқ, сервер доим дарҳол жонли) → табрик → панел.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../data/restaurants_repository.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'opened_celebration.dart';
import 'restaurant_form_fields.dart';
import 'restaurant_panel_screen.dart';
import 'restaurant_register_form.dart';
import 'dart:async';
import '../../tv_market/services/tv_clip_link.dart';
import '../../tv_market/widgets/tv_clip_link_widgets.dart';

class RestaurantRegisterScreen extends StatefulWidget {
  const RestaurantRegisterScreen({super.key, this.repository, this.homeCook = false});

  final RestaurantsRepository? repository;

  /// `true` — «Уй ошпази бўлиш»: `legalType` `individual` га қотирилади,
  /// танлов кўрсатилмайди. `false` — кафе-ресторан: фақат `yatt`/`llc`.
  final bool homeCook;

  @override
  State<RestaurantRegisterScreen> createState() => _RestaurantRegisterScreenState();
}

class _RestaurantRegisterScreenState extends State<RestaurantRegisterScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late final _data = RestaurantFormData(
    legalType: widget.homeCook ? RestaurantFormData.homeCookLegalType : RestaurantFormData.cafeLegalTypes.first,
    // Кафе-ресторан янги рўйхатдан ўтишда тур танлаши шарт (D-REST-41); уй ошпази — автомат home (сервер).
    venueRequired: !widget.homeCook,
  );
  bool _sending = false;
  bool _phoneLoaded = false;

  /// Бир форма = бир калит (C-2): таймаутдан кейин «Юбориш» қайта босилса ҳам
  /// сервер иккинчи ресторан очмайди — биринчи натижани қайтаради.
  final String _requestId = newRequestId();

  /// Охирги муваффақиятсиз юборишдаги хато калитлари: майдон остида кўрсатилади,
  /// эга тузатган сайин камаяди.
  Set<String> _errors = const {};
  final Map<String, GlobalKey> _anchors = {
    for (final k in const ['name', 'venue_type', 'location', 'address', 'payment_method', 'card_number']) k: GlobalKey(),
  };

  /// Рўйхатдан ўтгач таомлар обзори видеосини жойлаш (ихтиёрий).
  bool _withVideo = false;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_phone') ?? '';
      if (raw.isNotEmpty) _data.contactPhone = raw;
    } catch (_) {}
    if (mounted) setState(() => _phoneLoaded = true);
  }

  Future<void> _submit() async {
    if (_sending) return;
    final errs = _data.validate();
    if (errs.isNotEmpty) {
      setState(() => _errors = errs.toSet());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_err_${errs.first}')), backgroundColor: Colors.red.shade700),
      );
      // Биринчи хато майдонига скролл: хато матни экрандан ташқарида қолмасин.
      final first = errs.where(_anchors.containsKey).firstOrNull;
      if (first != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _anchors[first]?.currentContext;
          if (ctx != null && ctx.mounted) {
            Scrollable.ensureVisible(ctx, alignment: 0.15, duration: const Duration(milliseconds: 250));
          }
        });
      }
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await _repo.register(_data.toRegisterPayload(), requestId: _requestId);
      if (!mounted) return;
      final rid = (res['restaurantId'] ?? '') as String;
      final status = (res['status'] ?? 'applied') as String;
      if (status == 'approved') {
        // Эга, 2026-10-31: очилиш — табрик (конфетти); «Панелга ўтиш» босилгач панел.
        await showOpenedCelebration(context, homeCook: widget.homeCook);
        if (!mounted) return;
      } else {
        // Эски сервер ёки қўлда тасдиқ (ҳозир сервер доим `approved`): аввалги хабар.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('restaurants_m_submitted_pending'))),
        );
      }
      final nav = Navigator.of(context);
      // `pushReplacement` панел ёпилгунча тугамайди — кутмаймиз.
      unawaited(nav.pushReplacement(
        MaterialPageRoute(builder: (_) => RestaurantPanelScreen(restaurantId: rid, repository: _repo)),
      ));
      // Ихтиёрий таомлар обзори видеоси: ресторан ЯРАТИЛДИ; видео бекор
      // қилинса/йиқилса таъсир йўқ.
      if (_withVideo && rid.isNotEmpty) {
        await TvClipLink.publish(nav, kind: TvClipLink.kindRestaurant, linkId: rid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr(widget.homeCook ? 'home_create_home_cook' : 'restaurants_m_register_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: !_phoneLoaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  RestaurantFormFields(
                    data: _data,
                    onChanged: () => setState(() {
                      if (_errors.isNotEmpty) _errors = _data.validate().toSet();
                    }),
                    errors: _errors,
                    anchors: _anchors,
                    showLegalType: !widget.homeCook,
                    showVenueType: !widget.homeCook,
                    legalTypeOptions: RestaurantFormData.cafeLegalTypes,
                  ),
                  const SizedBox(height: 8),
                  VideoOptionTile(
                    value: _withVideo,
                    onChanged: (v) => setState(() => _withVideo = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.brandInk,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr('restaurants_m_submit'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
    );
  }
}
