import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../ev_charging/screens/ev_charging_map_screen.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../restaurants/screens/restaurant_screen.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../domain/business.dart';
import '../domain/business_pin.dart';
import '../domain/website_link.dart';

/// Нуқта босилганда чиқадиган тўлиқ маълумот варағи (эга қарори: «танлаб босилганда тўлиқ маълумот»).
///
/// Матн фақат берилган майдонларни кўрсатади (бўш қатор йўқ). Кафе ва зарядка станцияси учун
/// ўз экранини очиш тугмаси бор; улгуржи сотувчи ва оддий объектда — қўнғироқ ва йўналиш.
class BusinessDetailSheet extends StatelessWidget {
  const BusinessDetailSheet({super.key, required this.pin, this.shopRepository});

  final BusinessPin pin;

  /// Тест учун; бўлмаса — ҳақиқий витрина репозиторийси.
  final TvShopRepository? shopRepository;

  static Future<void> show(BuildContext context, BusinessPin pin) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => BusinessDetailSheet(pin: pin),
    );
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
              Text(pin.subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
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
                          builder: (_) => TvShopPublicScreen(ownerPhone: origin.ownerId, businessId: origin.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(context.tr('shop_go_to_shop')),
                  ),
                if (origin is Restaurant)
                  OutlinedButton.icon(
                    onPressed: () {
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

/// Объектнинг маҳсулот/хизматлари (фақат фаол ва ЭГАСИ ўзи ёзганлар): горизонтал қатор, босилса — детал.
/// Битта сўров (usinessId), фақат шу варақ очилганда; харита ва рўйхатда ўқиш йўқ (36-банд).
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
              Text(context.tr('bizprod_section'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
                          builder: (_) => TvShopItemDetailScreen(item: it, showShopButton: true, similarPool: items),
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
                            if (it.hasPrice)
                              Text(formatMoney(it.price), maxLines: 1, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
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
