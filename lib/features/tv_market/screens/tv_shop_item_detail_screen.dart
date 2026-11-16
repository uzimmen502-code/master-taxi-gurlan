import 'package:flutter/material.dart';

import '../../favorites/domain/favorite_ref.dart';
import '../../favorites/widgets/favorite_heart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../../../shared/widgets/product_mini_tile.dart';
import '../../../shared/widgets/seller_other_products_row.dart';
import '../../business_orders/screens/business_cart_screen.dart';
import '../../business_orders/widgets/business_order_entry.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../../markets/widgets/market_attrs_section.dart';
import '../domain/similar_items.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/shop_stats_recorder.dart';
import '../widgets/shop_complaint_sheet.dart';
import '../widgets/shop_unavailable_view.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_shop_item_card.dart';
import 'tv_market_feed_screen.dart';
import 'tv_shop_public_screen.dart';

/// Тафсилот фони — свайп қобиғи ([TvShopItemSwipeScreen]) ҳам шу рангда.
const Color kTvShopItemDetailBg = Color(0xFFF6F7F9);

/// Харидор товар детал: зум галерея + қўнғироқ + «Ўхшаш маҳсулотлар» + сотувчи дўконига ўтиш.
///
/// Очилганда маҳсулот ҳолати қайта ўқилади (эга қарори 2026-10-25: админ блоки барча кириш йўлларида): эски
/// рўйхат, видео ёки ҳавола орқали келинганда ҳам блокланган/ўчирилган маҳсулот кўрсатилмайди.
class TvShopItemDetailScreen extends StatefulWidget {
  const TvShopItemDetailScreen({
    super.key,
    required this.item,
    this.onOpenShop,
    this.showShopButton = false,
    this.similarPool = const [],
    this.loadLatest,
    this.submitComplaint,
    this.source = 'other',
    this.loadTaxonomy,
    this.countSellerActive,
  });

  /// Тест учун: сотувчининг фаол маҳсулотлари сони (бўлмаса [TvShopRepository.countActiveByOwner]).
  final Future<int> Function()? countSellerActive;

  /// Тест учун: бозор таксономияси (бўлмаса сеанс кешидан, [MarketAttrsSection]).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  /// Статистика манбаи (`ShopStatsRecorder.sources`).
  final String source;

  final TvShopItem item;

  /// Ўз дўкон очиш амали (эски чақирувчилар учун). Бўлмаса ва [showShopButton] — ягона онлайн дўкон
  /// маҳсулотнинг ЎЗ йўналиши билан очилади (`businessId`), бошқа йўналиш ёки умумий саҳифа эмас.
  final VoidCallback? onOpenShop;
  final bool showShopButton;

  /// «Ўхшаш маҳсулотлар» манбаи — чақирувчи экранда юкланган рўйхат (янги ўқиш йўқ). Бўш — қатор йўқ.
  final Iterable<TvShopItem> similarPool;

  /// Тест учун алмаштирилади; бўлмаса `TvShopRepository().fetchItem` (битта ўқиш).
  final Future<TvShopItem?> Function(String itemId)? loadLatest;

  /// Тест учун алмаштирилади; бўлмаса `submitShopComplaint` callable.
  final Future<void> Function({required String targetType, required String targetId, required String reason})?
      submitComplaint;

  @override
  State<TvShopItemDetailScreen> createState() => _TvShopItemDetailScreenState();
}

class _TvShopItemDetailScreenState extends State<TvShopItemDetailScreen> {
  late TvShopItem _item = widget.item;
  late bool _available = widget.item.isActive;

  /// «Ёзиш» (сотувчи билан чат, эга 2026-11-01).
  String _myUid = '';
  bool _writeBusy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
      if (mounted && uid != _myUid) setState(() => _myUid = uid);
    } catch (_) {
      // Рақам ўқилмаса — меҳмон ҳолати («Ёзиш» босилса рўйхатдан ўтишга чақирилади).
    }
  }

  Future<void> _writeSeller() async {
    if (_writeBusy) return;
    if (_myUid.length >= 11) setState(() => _writeBusy = true);
    try {
      await openDealChatFlow(context,
          productId: _item.id, myUid: _myUid, source: DealChatSource.shopItem);
    } finally {
      if (mounted) setState(() => _writeBusy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final load = widget.loadLatest ?? TvShopRepository().fetchItem;
      final fresh = await load(widget.item.id);
      if (!mounted) return;
      setState(() {
        if (fresh == null) {
          _available = false;
        } else {
          _item = fresh;
          _available = fresh.isActive;
        }
      });
      // Статистика (6-босқич): сервер тасдиқлаган фаол маҳсулот кўриши.
      if (fresh != null && fresh.isActive) {
        ShopStatsRecorder.productView(ownerPhone: fresh.ownerPhone, itemId: fresh.id, source: widget.source);
      }
    } catch (e) {
      // Тармоқ хатоси: қўлдаги нусха кўрсатилади (рўйхатлар ҳам фақат фаолини беради).
      debugPrint('[TvShopItemDetail] refresh: $e');
    }
  }

  Future<void> _call(BuildContext context) async {
    final ok = await callPhone(_item.ownerPhone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openClip(BuildContext context) async {
    final item = _item;
    if (item.clipIds.isEmpty) return;
    final clips = await TvClipsRepository().fetchByOwner(item.ownerPhone);
    TvClip? clip;
    for (final id in item.clipIds) {
      final hit = clips.where((c) => c.id == id && c.isActive);
      if (hit.isNotEmpty) {
        clip = hit.first;
        break;
      }
    }
    if (clip == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    );
  }

  VoidCallback? get _openShop {
    if (widget.onOpenShop != null) return widget.onOpenShop;
    if (!widget.showShopButton) return null;
    final item = _item;
    return () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TvShopPublicScreen(
              ownerPhone: item.ownerPhone,
              businessId: item.businessId,
              highlightItemId: item.id,
              source: 'product',
              ownerDisplayName: item.ownerName,
              districtLabel: item.districtLabel,
              districtId: item.districtId,
            ),
          ),
        );
  }

  void _openSimilar(TvShopItem other) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvShopItemDetailScreen(
          item: other,
          showShopButton: widget.showShopButton || widget.onOpenShop != null,
          similarPool: widget.similarPool,
          source: widget.source,
        ),
      ),
    );
  }

  Widget _similarStrip(List<TvShopItem> similar) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(context.tr('platform_store_similar'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        // Улгуржидаги карта билан БИР ХИЛ ([ProductMiniTile], эга 2026-11-03): аввал
        // 236 px лентада 160 px карта таги бўш қоларди.
        SizedBox(
          height: ProductMiniTile.stripHeight(context),
          child: ListView.separated(
            key: const ValueKey('shop_item_similar'),
            scrollDirection: Axis.horizontal,
            itemCount: similar.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = similar[i];
              final sPrice = s.priceLabel(context.tr);
              return ProductMiniTile(
                key: ValueKey('shop-similar-${s.id}'),
                imageUrl: s.coverPhotoUrl,
                title: s.title,
                price: sPrice.isEmpty ? null : sPrice,
                subtitle: s.ownerName,
                border: true,
                onTap: () => _openSimilar(s),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final openShop = _available ? _openShop : null;
    final similar = _available ? similarItems(item, widget.similarPool) : const <TvShopItem>[];
    return Scaffold(
      backgroundColor: kTvShopItemDetailBg,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        title: Text(_available ? item.title : '', maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0.4,
        // Дўкон иконкаси олиб ташланди (эга, 2026-10-31): нимани очиши
        // тушунарсиз эди ва пастдаги тугманинг такрори — энди сотувчи
        // қатори ([SellerOtherProductsRow], 2026-11-16).
        actions: [
          // «Сават» (STAGE 11) — саватда нарса бўлса.
          const BusinessCartButton(color: Colors.black87),
          // ❤ Танланганлар (STAGE 10).
          if (_available) FavoriteHeart(favorite: FavoriteRef.fromShopItem(item), overlay: false),
          if (_available)
            IconButton(
              key: const ValueKey('shop_item_report'),
              tooltip: context.tr('ad_report_title'),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showShopComplaintSheet(
                context,
                targetType: 'shop_item',
                targetId: _item.id,
                submit: widget.submitComplaint,
              ),
            ),
        ],
      ),
      body: !_available
          ? const ShopUnavailableView(textKey: 'product_unavailable')
          // Android 12+ «чўзилиш» эффекти ўчирилган (эга, 2026-10-31: ўхшашлар
          // бўлса саҳифа охирида чўзилиб қоларди). Свайп қобиғида ҳам
          // [kEdgeSwipePhysics] керак — контент қисқа бўлса ҳам кейингига ўтилсин.
          : ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: ListView(
              physics: kEdgeSwipePhysics,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                TvShopItemCard(
                  item: item,
                  onVideo: item.hasVideo ? () => _openClip(context) : null,
                ),
                // «Бозорлар» 6-босқич: бозор майдонлари (таксономия номлари билан; Аралаш/эски ҳужжатда йўқ).
                if (item.market.isNotEmpty)
                  MarketAttrsSection(
                    key: ValueKey('market_attrs_${item.id}'),
                    market: item.market,
                    category: item.category,
                    attrs: item.attrs,
                    imported: item.imported,
                    loadTaxonomy: widget.loadTaxonomy,
                  ),                // «<Сотувчи> · Сотувчининг бошқа маҳсулотлари →» — маҳсулот маълумоти остида ягона қатор; фақат
                // сотувчида 1 тадан кўп фаол маҳсулот бўлса (эга, 2026-11-16; аввалги сотувчи карточкаси ўрнига).
                if (openShop != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SellerOtherProductsRow(
                      cacheKey: item.businessId.isNotEmpty
                          ? 'tv_biz:${item.businessId}'
                          : 'tv:${canonicalPhoneId(item.ownerPhone)}',
                      sellerName: item.ownerName.trim().isEmpty ? context.tr('tv_vitrine_seller') : item.ownerName,
                      color: Colors.black87,
                      countActive: widget.countSellerActive ??
                          () => TvShopRepository().countActiveByOwner(item.ownerPhone, businessId: item.businessId),
                      onOpen: openShop,
                    ),
                  ),
                // «Саватга қўшиш» / «Етказиш нархини сўраш» (AVA курьери): объект ва ўз дўкони маҳсулоти (STAGE 11); фақат
                // дарвоза очиқ ва маҳсулот/сотувчи мос бўлса кўринади ([BusinessOrderEntry] ўзи текширади; бўлмаса — ҳеч нарса).
                BusinessOrderEntry(key: ValueKey('biz_order_entry_${item.id}'), item: item, myUid: _myUid),

                if (similar.isNotEmpty) _similarStrip(similar),
              ],
            ),
            ),
      bottomNavigationBar: _available
          ? TvChannelContactBar(
              onCall: () => _call(context),
              // ЎЗ маҳсулотида «Ёзиш» йўқ (сервер ҳам OWN_PRODUCT).
              onWrite: dealChatShowWrite(myUid: _myUid, ownerPhone: item.ownerPhone) ? _writeSeller : null,
              writeBusy: _writeBusy,
            )
          : null,
    );
  }
}
