import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
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
import '../widgets/tv_shop_item_grid_card.dart';
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
  });

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

  @override
  void initState() {
    super.initState();
    _refresh();
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
        SizedBox(
          height: 236,
          child: ListView.separated(
            key: const ValueKey('shop_item_similar'),
            scrollDirection: Axis.horizontal,
            itemCount: similar.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: 160,
              child: TvShopItemGridCard(item: similar[i], onTap: () => _openSimilar(similar[i])),
            ),
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
        actions: [
          if (openShop != null)
            IconButton(
              key: const ValueKey('shop_item_open_shop'),
              tooltip: context.tr('tv_shop_mine'),
              onPressed: openShop,
              icon: const Icon(Icons.storefront_outlined),
            ),
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
                if (openShop != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      key: const ValueKey('shop_item_go_shop'),
                      onPressed: openShop,
                      icon: const Icon(Icons.storefront_rounded),
                      label: Text(context.tr('shop_go_to_shop')),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                if (similar.isNotEmpty) _similarStrip(similar),
              ],
            ),
            ),
      bottomNavigationBar: _available ? TvChannelContactBar(onCall: () => _call(context)) : null,
    );
  }
}
