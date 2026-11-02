import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../deal_chat/data/deal_chat_repository.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../../ev_charging/screens/ev_charging_map_screen.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../restaurants/open_restaurant_checked.dart';
import '../../restaurants/screens/restaurant_screen.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../tv_market/services/shop_stats_recorder.dart';
import '../domain/business.dart';
import '../domain/business_pin.dart';
import '../domain/business_subtypes.dart';
import '../domain/business_type_profile.dart';
import '../domain/website_link.dart';

/// Нуқта босилганда чиқадиган тўлиқ маълумот варағи (эга қарори: «танлаб босилганда тўлиқ маълумот»).
///
/// Матн фақат берилган майдонларни кўрсатади (бўш қатор йўқ). Кафе ва зарядка станцияси учун
/// ўз экранини очиш тугмаси бор (ресторан бўлимига уланган объектда ҳам «Меню»); улгуржи сотувчи ва оддий
/// объектда — қўнғироқ ва йўналиш.
class BusinessDetailSheet extends StatelessWidget {
  const BusinessDetailSheet({
    super.key,
    required this.pin,
    this.shopRepository,
    this.loadRestaurant,
    this.pushScreen,
    this.dealChatRepository,
  });

  final BusinessPin pin;

  /// Тест учун: «Ёзиш» чат репозиторийси; бўлмаса — ҳақиқий (Firebase).
  final DealChatRepository? dealChatRepository;

  /// Тест учун; бўлмаса — ҳақиқий витрина репозиторийси.
  final TvShopRepository? shopRepository;

  /// Тест учун: уланган ресторанни ўқиш; бўлмаса — `RestaurantsRepository().getRestaurant`.
  final Future<Restaurant?> Function(String id)? loadRestaurant;

  /// Тест учун: уланган ресторан менюси навигаторга қўшилиш ўрнига шу ерга берилади (варақ барибир ёпилади).
  final void Function(Widget screen)? pushScreen;

  static Future<void> show(BuildContext context, BusinessPin pin) {
    recordView(pin);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => BusinessDetailSheet(pin: pin),
    );
  }

  /// Эгаси бор объект варағи очилди → дўкон кўриши (`shop_view`, йўналиш = шу объект, манба `map`); санашни
  /// сервер қилади (`recordShopEvent`), ресторан белгисидаги «Меню» каби. Ёзгич сессияда бир марта юборади —
  /// кейин «Дўконга ўтиш» (ўша калит) иккинчи марта санамайди.
  static void recordView(BusinessPin pin) {
    final origin = pin.origin;
    if (origin is! Business || origin.isBlocked || origin.id.isEmpty) return;
    if (phoneDigits(origin.ownerId).length < 9) return;
    ShopStatsRecorder.shopView(ownerPhone: origin.ownerId, businessId: origin.id, source: 'map');
  }

  /// Умумий `callPhone` (кафе, юк, такси ва бошқа экранлар билан бир хил): рақам яроқсиз бўлса ёки
  /// телефон иловаси йўқ бўлса — жим қолмай хабар кўрсатади.
  Future<void> _call(BuildContext context) async {
    final ok = await callPhone(pin.phone);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(context.tr('tv_market_call_failed'))));
  }

  Future<void> _openWebsite() async {
    final uri = websiteUri(pin.website);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final origin = pin.origin;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(pin.category.icon, size: 20, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr(pin.category.labelKey),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(pin.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (pin.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                // Тайёр аниқроқ тур — кўрувчи тилида (эга бошқа тилда танлаган бўлса ҳам); эркин матн — ўзи.
                pin.source == BusinessSource.business
                    ? BusinessSubtypes.display(pin.subtitle, context.contentLang, category: pin.category)
                    : pin.subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 14),
            if (pin.description.isNotEmpty)
              _Line(icon: Icons.notes_rounded, text: pin.description),
            if (pin.address.isNotEmpty)
              _Line(icon: Icons.place_outlined, text: pin.address),
            if (pin.hours.isNotEmpty)
              _Line(icon: Icons.schedule_rounded, text: pin.hours),
            if (pin.phone.isNotEmpty)
              _Line(icon: Icons.phone_outlined, text: pin.phone, onTap: () => _call(context)),
            if (pin.website.isNotEmpty)
              _Line(icon: Icons.public_rounded, text: pin.website, onTap: websiteUri(pin.website) == null ? null : _openWebsite),
            if (origin is Business) _ProductsStrip(business: origin, repository: shopRepository),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pin.phone.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(context.tr('bizmap_call')),
                  ),
                // «Ёзиш» — объект эгаси билан чат (source business, сервер 2026-11-03). Ўз объектида ва
                // блокланганда йўқ; эгасиз (админ қўшган) объектда йўқ — сервер ҳам рад этади.
                if (origin is Business && !origin.isBlocked && origin.id.isNotEmpty)
                  _BusinessWriteButton(business: origin, repository: dealChatRepository),
                OutlinedButton.icon(
                  onPressed: () => openMapsNavigation(lat: pin.lat, lng: pin.lng, label: pin.name),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: Text(context.tr('bizmap_route')),
                ),
                // Харита нуқтаси → ЎША онлайн дўкон, айнан шу йўналиш танланган (эга қарори 2026-10-25).
                // Эгасиз (админ қўшган) объектнинг онлайн дўкони йўқ — тугма ҳам йўқ.
                if (origin is Business && !origin.isBlocked && phoneDigits(origin.ownerId).length >= 9)
                  OutlinedButton.icon(
                    key: const ValueKey('biz_open_shop'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TvShopPublicScreen(ownerPhone: origin.ownerId, businessId: origin.id, source: 'map'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    // Тур профилидан: дўкон — «Дўконга ўтиш», хизмат — «Барча хизматлар», бошқаси — «Саҳифага ўтиш».
                    label: Text(context.tr(BusinessTypeProfile.forBusiness(origin).openCatalogKey)),
                  ),
                // Ресторан бўлимига уланган объект: ресторан белгиси харитада шу белгига қўшилган (эга, 2026-11-03),
                // меню шу ердан очилади. «Дўконга ўтиш» ҳам қолади (кафенинг маҳсулотлари бўлиши мумкин).
                if (origin is Business && origin.hasRestaurant && !origin.isBlocked)
                  _LinkedMenuButton(
                    restaurantId: origin.restaurantId,
                    loadRestaurant: loadRestaurant,
                    pushScreen: pushScreen,
                  ),
                if (origin is Restaurant)
                  OutlinedButton.icon(
                    onPressed: () {
                      ShopStatsRecorder.restaurantView(restaurantId: origin.id, source: 'map');
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => RestaurantScreen(restaurant: origin)),
                      );
                    },
                    icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                    label: Text(context.tr('bizmap_open_menu')),
                  ),
                if (pin.source == BusinessSource.evStation)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const EvChargingMapScreen()),
                      );
                    },
                    icon: const Icon(Icons.ev_station_rounded, size: 18),
                    label: Text(context.tr('bizmap_open_ev')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «Ёзиш» — объект эгаси билан чат ([DealChatSource.business]). Жорий рақам (`user_phone`) ўқилгунча кўринмайди;
/// ўз объектида — йўқ ([dealChatShowWrite]); меҳмонга кўринади, босганда рўйхатдан ўтишга чақирилади.
/// Чат варақ устида очилади (ёпилса — варақ қайтади); меҳмон ёки хато бўлса варақ ёпилади — хабар харитада.
class _BusinessWriteButton extends StatefulWidget {
  const _BusinessWriteButton({required this.business, this.repository});

  final Business business;
  final DealChatRepository? repository;

  @override
  State<_BusinessWriteButton> createState() => _BusinessWriteButtonState();
}

class _BusinessWriteButtonState extends State<_BusinessWriteButton> {
  String? _myUid;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    var uid = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    } catch (_) {
      // Рақам ўқилмаса — меҳмон ҳолати.
    }
    if (mounted) setState(() => _myUid = uid);
  }

  Future<void> _write() async {
    final me = _myUid ?? '';
    if (_busy) return;
    if (me.length >= 11) setState(() => _busy = true);
    final opened = await openDealChatFlow(
      context,
      productId: widget.business.id,
      myUid: me,
      source: DealChatSource.business,
      repository: widget.repository,
    );
    if (!mounted) return;
    if (!opened && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = _myUid;
    if (me == null || !dealChatShowWrite(myUid: me, ownerPhone: widget.business.ownerId)) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: const ValueKey('biz_write'),
      onPressed: _busy ? null : _write,
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chat_bubble_outline, size: 18),
      label: Text(context.tr('deal_chat_write')),
    );
  }
}

/// Уланган ресторан менюсини очиш. Ресторан ОЧИШ ВАҚТИДА ўқилади ва текширилади — ҳавола/қидирув билан бир хил
/// [openRestaurantChecked]: йўқ, тасдиқланмаган ёки ўқиб бўлмаса — «вақтинча мавжуд эмас». Ўқиш давомида тугма
/// ўчиқ ва айланувчи белги (иккинчи босиш янги сўров очмайди).
class _LinkedMenuButton extends StatefulWidget {
  const _LinkedMenuButton({required this.restaurantId, this.loadRestaurant, this.pushScreen});

  final String restaurantId;
  final Future<Restaurant?> Function(String id)? loadRestaurant;
  final void Function(Widget screen)? pushScreen;

  @override
  State<_LinkedMenuButton> createState() => _LinkedMenuButtonState();
}

class _LinkedMenuButtonState extends State<_LinkedMenuButton> {
  bool _loading = false;

  /// Варақ ҳали очиқ ва энг устида (фойдаланувчи ўқиш пайтида ёпмаган) — шундагина `pop` варақни ёпади;
  /// акс ҳолда `pop` остидаги харита экранини ёпиб юборарди.
  bool get _sheetOnTop => mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    var opened = false;
    await openRestaurantChecked(
      context,
      widget.restaurantId,
      source: 'map',
      load: widget.loadRestaurant,
      // Харитадаги ресторан белгисининг «Меню»си ҳам модул дарвозасисиз очилади — бу белги ўшанинг ўрнида,
      // хатти-ҳаракати бир хил қолади (харитада дарвоза йўқ).
      canOpenModule: () async => true,
      push: (screen) {
        if (!_sheetOnTop) return;
        opened = true;
        final nav = Navigator.of(context);
        nav.pop();
        final push = widget.pushScreen;
        if (push != null) return push(screen);
        nav.push(MaterialPageRoute<void>(builder: (_) => screen));
      },
    );
    if (!mounted || opened) return;
    // Очилмади: «вақтинча мавжуд эмас» хабари харита экранида — варақ уни ёпиб туради, шунинг учун варақ ёпилади.
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('biz_open_menu'),
      onPressed: _loading ? null : _open,
      icon: _loading
          ? const SizedBox(
              key: ValueKey('biz_open_menu_loading'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.restaurant_menu_rounded, size: 18),
      label: Text(context.tr('bizmap_open_menu')),
    );
  }
}

/// Объектнинг маҳсулот/хизматлари (фақат фаол ва ЭГАСИ ўзи ёзганлар): горизонтал қатор, босилса — детал.
/// Битта сўров (`businessId`), фақат шу варақ очилганда; харита ва рўйхатда ўқиш йўқ (36-банд).
class _ProductsStrip extends StatefulWidget {
  const _ProductsStrip({required this.business, this.repository});

  final Business business;
  final TvShopRepository? repository;

  @override
  State<_ProductsStrip> createState() => _ProductsStripState();
}

class _ProductsStripState extends State<_ProductsStrip> {
  late final Future<List<TvShopItem>> _future = _load();

  Future<List<TvShopItem>> _load() async {
    try {
      return await (widget.repository ?? TvShopRepository())
          .fetchByBusiness(widget.business.id, ownerPhone: widget.business.ownerId, limit: 40);
    } catch (_) {
      return const []; // каталог ўқилмаса — карточканинг қолган қисми ишлайверади
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TvShopItem>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <TvShopItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr(BusinessTypeProfile.forBusiness(widget.business).offersSectionKey),
                  key: const ValueKey('biz_products_title'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  key: const ValueKey('biz_products_strip'),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final cover = it.coverPhotoUrl;
                    return InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TvShopItemDetailScreen(item: it, showShopButton: true, similarPool: items, source: 'map'),
                        ),
                      ),
                      child: SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 96,
                                height: 76,
                                child: cover.isEmpty
                                    ? const ColoredBox(color: Color(0x11000000))
                                    : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x11000000))),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            if (it.priceLabel(context.tr).isNotEmpty)
                              Text(it.priceLabel(context.tr), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: onTap == null ? null : AppColors.primaryDark,
                decoration: onTap == null ? null : TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
