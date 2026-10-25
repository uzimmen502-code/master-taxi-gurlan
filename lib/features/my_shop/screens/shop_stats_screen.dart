import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../tv_market/repositories/tv_public_profiles_repository.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../shop_stats.dart';

/// Статистика экранининг матн калитлари. [showVideoTotal] — АВАГрам жами кўришлари (эга телефони бўйича; ресторанда
/// бир неча а'зо бўлгани учун кўрсатилмайди — ўлчанмаган рақам кўрсатилмасин).
class ShopStatsLabels {
  const ShopStatsLabels({
    required this.mainViews,
    required this.itemViews,
    required this.topItems,
    required this.rules,
    required this.since,
    this.showVideoTotal = true,
  });

  final String mainViews;
  final String itemViews;
  final String topItems;
  final String rules;
  final String since;
  final bool showVideoTotal;

  static const shop = ShopStatsLabels(
    mainViews: 'stats_shop_views',
    itemViews: 'stats_product_views',
    topItems: 'stats_top_products',
    rules: 'stats_rules',
    since: 'stats_since',
  );

  static const restaurant = ShopStatsLabels(
    mainViews: 'stats_restaurant_views',
    itemViews: 'stats_dish_views',
    topItems: 'stats_top_dishes',
    rules: 'stats_rules_restaurant',
    since: 'stats_since_restaurant',
    showVideoTotal: false,
  );
}

/// Сотувчи статистикаси (эга қарори 2026-10-25, 6-босқич). Фақат ЎЛЧАНГАН рақамлар: дўкон ва маҳсулот кўришлари
/// (бир харидор бир кунда бир марта, эгасининг ўзи саналмайди), қаердан келишгани, энг кўп кўрилган маҳсулотлар;
/// АВАГрам видео кўришлари — мавжуд ҳисоблагичдан (жами). Тахминий ёки ўлчанмаган рақам кўрсатилмайди.
/// Кафе-ресторан ҳам шу экранни ишлатади ([ShopStatsLabels.restaurant], 2026-10-25).
class ShopStatsScreen extends StatefulWidget {
  const ShopStatsScreen({
    super.key,
    required this.phone,
    this.loadSummary,
    this.loadTitles,
    this.loadVideoViews,
    this.labels = ShopStatsLabels.shop,
  });

  final String phone;

  /// Матн калитлари: дўкон (стандарт) ёки кафе-ресторан ([ShopStatsLabels.restaurant]) — экран ва ҳисоб бир хил.
  final ShopStatsLabels labels;

  /// Тест учун алмаштирилади.
  final Future<ShopStatsSummary> Function(int days)? loadSummary;
  final Future<Map<String, String>> Function()? loadTitles;
  final Future<int> Function()? loadVideoViews;

  @override
  State<ShopStatsScreen> createState() => _ShopStatsScreenState();
}

class _ShopStatsScreenState extends State<ShopStatsScreen> {
  int _days = 7;
  late Future<ShopStatsSummary> _summary = _load();
  late final Future<Map<String, String>> _titles = _loadTitles();
  late final Future<int> _videoViews = _loadVideo();

  static const _sourceKeys = [
    'market', 'list', 'home', 'search', 'video', 'map', 'section', 'restaurant', 'product', 'link', 'qr', 'shop', 'other',
  ];

  Future<ShopStatsSummary> _load() =>
      (widget.loadSummary ?? (d) => ShopStatsRepository().fetch(widget.phone, days: d))(_days);

  Future<Map<String, String>> _loadTitles() async {
    try {
      if (widget.loadTitles != null) return await widget.loadTitles!();
      final items = await TvShopRepository().fetchByOwner(widget.phone, limit: 200);
      return {for (final i in items) i.id: i.title};
    } catch (e) {
      debugPrint('[ShopStats] titles: $e');
      return const {};
    }
  }

  Future<int> _loadVideo() async {
    try {
      if (widget.loadVideoViews != null) return await widget.loadVideoViews!();
      return await TvPublicProfilesRepository().fetchTotalViewCount(widget.phone);
    } catch (e) {
      debugPrint('[ShopStats] video: $e');
      return 0;
    }
  }

  void _setDays(int d) => setState(() {
        _days = d;
        _summary = _load();
      });

  Widget _tile(String labelKey, int value, IconData icon, {Key? key}) => Expanded(
        child: Card(
          key: key,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primaryDark),
                const SizedBox(height: 8),
                Text('$value', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                Text(context.tr(labelKey), style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('stats_title'))),
      body: FutureBuilder<ShopStatsSummary>(
        future: _summary,
        builder: (context, snap) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 7, label: Text(context.tr('stats_days_7'), key: const ValueKey('stats_7'))),
                  ButtonSegment(value: 30, label: Text(context.tr('stats_days_30'), key: const ValueKey('stats_30'))),
                ],
                selected: {_days},
                onSelectionChanged: (s) => _setDays(s.first),
              ),
              const SizedBox(height: 12),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.tr('bizprod_err_generic'), textAlign: TextAlign.center),
                )
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                _body(snap.data!),
              ],
              if (widget.labels.showVideoTotal) ...[
                const SizedBox(height: 12),
                FutureBuilder<int>(
                  future: _videoViews,
                  builder: (context, v) => Card(
                    key: const ValueKey('stats_video_total'),
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.play_circle_outline_rounded, color: AppColors.primaryDark),
                      title: Text(context.tr('stats_video_total')),
                      trailing: Text('${v.data ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(context.tr(widget.labels.rules), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(context.tr(widget.labels.since), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(ShopStatsSummary s) {
    final sources = [for (final k in _sourceKeys) if (s.src(k) > 0) k];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          _tile(widget.labels.mainViews, s.shopViews, Icons.storefront_rounded, key: const ValueKey('stats_shop_views')),
          const SizedBox(width: 10),
          _tile(widget.labels.itemViews, s.productViews, Icons.inventory_2_outlined, key: const ValueKey('stats_product_views')),
        ]),
        const SizedBox(height: 16),
        Text(context.tr('stats_sources'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        if (sources.isEmpty)
          Text(context.tr('stats_empty'), key: const ValueKey('stats_empty'))
        else
          for (final k in sources)
            ListTile(
              key: ValueKey('stats_src_$k'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('stats_src_$k')),
              trailing: Text('${s.src(k)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        if (s.topItems().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(context.tr(widget.labels.topItems), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          FutureBuilder<Map<String, String>>(
            future: _titles,
            builder: (context, t) => Column(
              children: [
                for (final e in s.topItems())
                  ListTile(
                    key: ValueKey('stats_item_${e.key}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((t.data ?? const {})[e.key] ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
