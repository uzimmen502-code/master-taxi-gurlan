import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../business_map/domain/business.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_market_feed_screen.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../vacancies/domain/job_vacancy.dart';
import '../../vacancies/screens/vacancies_screen.dart';
import '../../vacancies/screens/vacancy_detail_screen.dart';
import '../../wholesale/models/wholesale_seller.dart';
import '../../wholesale/repositories/wholesale_sellers_repository.dart';
import '../../wholesale/screens/wholesale_seller_products_screen.dart';
import '../domain/factory_profile.dart';
import 'factory_manage_screen.dart';

/// Завод саҳифаси (эга 2026-11-28): ҳақида, жойлашув, маҳсулотлар, видеолар, вакансиялар, Улгуржи.
/// Видео / вакансия / Улгуржи блоклари — фақат завод ЎЗИ ёқса (`factory.*`, [FactoryManageScreen]).
/// Телефон кўрсатилмайди: «Ёзиш» — мавжуд объект чати (`openDealChat` source `business`).
class FactoryPageScreen extends StatefulWidget {
  const FactoryPageScreen({
    super.key,
    required this.business,
    this.myUid,
    this.loadProducts,
    this.loadClips,
    this.loadVacancies,
    this.loadSeller,
  });

  final Business business;

  @visibleForTesting
  final String? myUid;
  @visibleForTesting
  final Future<List<TvShopItem>> Function(Business b)? loadProducts;
  @visibleForTesting
  final Future<List<TvClip>> Function(Business b)? loadClips;
  @visibleForTesting
  final Future<List<JobAd>> Function(Business b)? loadVacancies;
  @visibleForTesting
  final Future<WholesaleSeller?> Function(Business b)? loadSeller;

  @override
  State<FactoryPageScreen> createState() => _FactoryPageScreenState();
}

class _FactoryPageScreenState extends State<FactoryPageScreen> {
  late final String _me =
      widget.myUid ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  late Business _b = widget.business;
  List<TvShopItem> _products = const [];
  List<TvClip> _clips = const [];
  List<JobAd> _vacancies = const [];
  WholesaleSeller? _seller;

  bool get _isOwner => _me.isNotEmpty && canonicalPhoneId(_b.ownerId) == _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Future<T> _safe<T>(Future<T> Function() f, T fallback, String code) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('[FactoryPage] $code: $e');
      return fallback;
    }
  }

  Future<void> _load() async {
    final b = _b;
    final o = b.factoryOptions;
    final results = await Future.wait<Object?>([
      _safe(() => widget.loadProducts?.call(b) ?? TvShopRepository().fetchByBusiness(b.id, ownerPhone: b.ownerId),
          const <TvShopItem>[], 'FACTORY_PRODUCTS_FAILED'),
      o.showVideos
          ? _safe(
              () async => (await (widget.loadClips?.call(b) ?? TvClipsRepository().fetchByOwner(b.ownerId, limit: 20)))
                  .where((c) => c.isActive && c.isPlayable)
                  .take(10)
                  .toList(),
              const <TvClip>[],
              'FACTORY_CLIPS_FAILED')
          : Future.value(const <TvClip>[]),
      o.publishVacancies
          ? _safe(
              () => widget.loadVacancies?.call(b) ??
                  JobsRepository().fetchEmployerVacancies(JobVacancy.employerKeyOf('business', b.id)),
              const <JobAd>[],
              'FACTORY_VACANCIES_FAILED')
          : Future.value(const <JobAd>[]),
      o.sellWholesale
          ? _safe(() => widget.loadSeller?.call(b) ?? WholesaleSellersRepository().fetchByPhone(b.ownerId), null,
              'FACTORY_SELLER_FAILED')
          : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0] as List<TvShopItem>;
      _clips = results[1] as List<TvClip>;
      _vacancies = results[2] as List<JobAd>;
      _seller = results[3] as WholesaleSeller?;
    });
  }

  Future<void> _manage() async {
    final updated = await Navigator.of(context).push<Business>(
      MaterialPageRoute(builder: (_) => FactoryManageScreen(business: _b)),
    );
    if (updated != null && mounted) {
      setState(() => _b = updated);
      await _load();
    }
  }

  Widget _title(String key) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(context.tr(key), style: AvaText.homeCardTitle.copyWith(color: context.ava.ink)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final b = _b;
    final district = GeoNames.district(b.districtId, context.contentLang);
    final seller = _seller;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(b.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isOwner)
            IconButton(
              key: const ValueKey('factory_manage'),
              tooltip: context.tr('factory_manage_title'),
              icon: const Icon(Icons.tune_rounded),
              onPressed: _manage,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Icon(b.category.icon, color: b.category.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(b.subtype.isNotEmpty ? b.subtype : context.tr(b.category.labelKey),
                  style: TextStyle(color: c.ink2)),
            ),
          ]),
          if (showsVerifiedProducerBadge(b)) ...[
            const SizedBox(height: 8),
            const VerifiedProducerBadge(),
          ],
          // ── Ҳақида ──
          _title('factory_about'),
          Text(b.description.isNotEmpty ? b.description : context.tr('factory_no_description'),
              key: const ValueKey('factory_description')),
          if (b.openingHours.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${context.tr('factory_hours')}: ${b.openingHours}', style: TextStyle(color: c.ink2)),
          ],
          // ── Жойлашув ──
          _title('factory_location'),
          Text([if (b.address.isNotEmpty) b.address, if (district.isNotEmpty) district].join(', ').ifEmpty(
              context.tr('factory_online'))),
          if (!_isOwner && dealChatShowWrite(myUid: _me, ownerPhone: b.ownerId)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('factory_write'),
              onPressed: () => openDealChatFlow(context, productId: b.id, myUid: _me, source: DealChatSource.business),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(context.tr('factory_write')),
            ),
          ],
          // ── Маҳсулотлар ──
          _title('factory_products'),
          if (_products.isEmpty)
            Text(context.tr('factory_no_products'), style: TextStyle(color: c.ink2))
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                key: const ValueKey('factory_products_list'),
                scrollDirection: Axis.horizontal,
                itemCount: _products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final p = _products[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                      builder: (_) => TvShopItemDetailScreen(item: p, similarPool: _products),
                    )),
                    child: SizedBox(
                      width: 120,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 120,
                            height: 96,
                            child: p.photoUrl.isEmpty
                                ? ColoredBox(color: c.surface2, child: Icon(Icons.inventory_2_outlined, color: c.ink3))
                                : Image.network(p.photoUrl, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => ColoredBox(color: c.surface2)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          // ── Видеолар (завод ёқса) ──
          if (b.factoryOptions.showVideos && _clips.isNotEmpty) ...[
            _title('factory_videos'),
            for (final clip in _clips)
              ListTile(
                key: ValueKey('factory_clip_${clip.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline_rounded),
                title: Text(clip.title.isNotEmpty ? clip.title : context.tr('factory_video'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip))),
              ),
          ],
          // ── Вакансиялар (завод ёқса) ──
          if (b.factoryOptions.publishVacancies) ...[
            _title('factory_vacancies'),
            if (_vacancies.isEmpty)
              Text(context.tr('factory_no_vacancies'), style: TextStyle(color: c.ink2))
            else
              for (final v in _vacancies) ...[
                VacancyCard(
                  ad: v,
                  onTap: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: (_) => VacancyDetailScreen(ad: v))),
                ),
                const SizedBox(height: 8),
              ],
          ],
          // ── Улгуржи (завод ёқса ва сотувчи тасдиқланган бўлса) ──
          if (b.factoryOptions.sellWholesale && seller != null && seller.isApproved) ...[
            _title('factory_wholesale'),
            FilledButton.tonalIcon(
              key: const ValueKey('factory_wholesale_open'),
              onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => WholesaleSellerProductsScreen(sellerId: seller.phone, sellerName: seller.companyName),
              )),
              icon: const Icon(Icons.inventory_rounded),
              label: Text(context.tr('factory_wholesale_open')),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// «Тасдиқланган ишлаб чиқарувчи» нишони.
class VerifiedProducerBadge extends StatelessWidget {
  const VerifiedProducerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('factory_verified_badge'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_rounded, size: 16, color: c.ok),
          const SizedBox(width: 4),
          Text(context.tr('factory_verified'), style: TextStyle(color: c.ok, fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      ),
    );
  }
}
