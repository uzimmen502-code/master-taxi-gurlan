import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../ads/models/ad_model.dart';
import '../../ads/repositories/ads_repository.dart';
import '../../ads/widgets/my_ad_actions.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';

/// Аҳоли бозори каталоги («Менинг дўконим»): ҳар маҳсулот РАСМ (7 тагача, биринчиси
/// кўринади) ва ВИДЕО билан. Уч ҳолат: Фаол · Текширувда · Яширилган.
///
/// Видео — мавжуд ягона қатлам ([TvClipLink], `market_ad`): эълон яратилганда ёки
/// ШУ ЕРДА кейин қўшилади; клип AVAGram лентасига ҳам тушади. Каталог учун клиплар
/// БИТТА сўров билан ўқилади (ҳар карта учун алоҳида эмас, 36-қоида).
class ShopAdsCatalog extends StatefulWidget {
  const ShopAdsCatalog({
    super.key,
    required this.uid,
    @visibleForTesting this.adsStream,
    @visibleForTesting this.loadClips,
    @visibleForTesting this.onAddVideo,
    @visibleForTesting this.onOpenVideo,
  });

  /// Каноник телефон (9+ рақам).
  final String uid;

  /// Тест учун: Firestore'га уланмайдиган алмаштиргичлар.
  final Stream<List<AdModel>> Function(String status)? adsStream;
  final Future<Map<String, TvClip>> Function(String uid)? loadClips;
  final Future<void> Function(BuildContext context, AdModel ad)? onAddVideo;
  final void Function(BuildContext context, TvClip clip)? onOpenVideo;

  @override
  State<ShopAdsCatalog> createState() => _ShopAdsCatalogState();
}

class _ShopAdsCatalogState extends State<ShopAdsCatalog> {
  late Future<Map<String, TvClip>> _clips = _loadClips();

  @override
  void initState() {
    super.initState();
    // Видео боғланганда (шу ерда ёки яратиш формасидан) клиплар қайта ўқилади.
    TvClipLink.changes.addListener(_reload);
  }

  @override
  void dispose() {
    TvClipLink.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    // Блок (=> эмас): `setState` Future қайтарувчи callback'ни қабул қилмайди.
    setState(() {
      _clips = _loadClips();
    });
  }

  /// `linkId → энг янги клип` (фақат шу эганики, фақат `market_ad`). Ўқилмаса —
  /// бўш: каталог расмлар билан ишлайверади, видео тугмаси «қўшиш» бўлиб қолади.
  Future<Map<String, TvClip>> _loadClips() async {
    try {
      final custom = widget.loadClips;
      if (custom != null) return await custom(widget.uid);
      final all = await TvClipsRepository().fetchByOwner(widget.uid);
      final out = <String, TvClip>{};
      for (final c in all) {
        if (c.linkKind == TvClipLink.kindMarket && c.linkId.isNotEmpty) {
          out.putIfAbsent(c.linkId, () => c); // янгиси биринчи
        }
      }
      return out;
    } catch (e) {
      debugPrint('[ShopAdsCatalog] clips failed: $e');
      return const {};
    }
  }

  Future<void> _addVideo(BuildContext context, AdModel ad) async {
    final custom = widget.onAddVideo;
    if (custom != null) return custom(context, ad);
    await TvClipLink.publish(
      Navigator.of(context),
      kind: TvClipLink.kindMarket,
      linkId: ad.id,
    );
  }

  void _openVideo(BuildContext context, TvClip clip) {
    final custom = widget.onOpenVideo;
    if (custom != null) return custom(context, clip);
    TvClipLink.open(context, clip);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              labelColor: AvaLight.ink,
              unselectedLabelColor: AppColors.sectionMuted,
              indicatorColor: AvaLight.ink,
              tabs: [
                Tab(text: context.tr('jobs_status_active')),
                Tab(text: context.tr('jobs_status_pending')),
                Tab(text: context.tr('wholesale_status_inactive')),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, TvClip>>(
              future: _clips,
              builder: (context, clipSnap) {
                final clips = clipSnap.data ?? const <String, TvClip>{};
                return TabBarView(
                  children: [
                    for (final status in const ['active', 'pending', 'inactive'])
                      _StatusGrid(
                        uid: widget.uid,
                        status: status,
                        stream: widget.adsStream,
                        clips: clips,
                        onAddVideo: _addVideo,
                        onOpenVideo: _openVideo,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.uid,
    required this.status,
    required this.stream,
    required this.clips,
    required this.onAddVideo,
    required this.onOpenVideo,
  });

  final String uid;
  final String status;
  final Stream<List<AdModel>> Function(String status)? stream;
  final Map<String, TvClip> clips;
  final Future<void> Function(BuildContext context, AdModel ad) onAddVideo;
  final void Function(BuildContext context, TvClip clip) onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final source = stream != null
        ? stream!(status)
        : context.read<AdsRepository>().getMyAds(uid, status: status);
    return StreamBuilder<List<AdModel>>(
      stream: source,
      builder: (context, snap) {
        if (snap.hasError) {
          // «Бўш» эмас: ўқиб бўлмади (25-банд — содда жумла, хато матни йўқ).
          return Center(child: Text(context.tr('cheap_products_load_error')));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ads = snap.data!;
        if (ads.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                context.tr('my_shop_catalog_empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.sectionMuted),
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.66,
          ),
          itemCount: ads.length,
          itemBuilder: (_, i) => _AdTile(
            ad: ads[i],
            pending: status == 'pending',
            clip: clips[ads[i].id],
            onAddVideo: onAddVideo,
            onOpenVideo: onOpenVideo,
          ),
        );
      },
    );
  }
}

class _AdTile extends StatelessWidget {
  const _AdTile({
    required this.ad,
    required this.pending,
    required this.clip,
    required this.onAddVideo,
    required this.onOpenVideo,
  });

  final AdModel ad;
  final bool pending;
  final TvClip? clip;
  final Future<void> Function(BuildContext context, AdModel ad) onAddVideo;
  final void Function(BuildContext context, TvClip clip) onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final photo = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : null;
    final c = clip;
    final videoPlayable = c != null && c.isActive && c.isPlayable;
    final videoPending = c != null && !videoPlayable && c.status == 'pending';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: AppColors.cardImageBg,
                      child: photo == null
                          ? const Icon(Icons.image_outlined, size: 40)
                          : CachedNetworkImage(
                              imageUrl: photo,
                              // contain: расм четлари қирқилмайди (эга, 2026-10-19).
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  if (ad.imageUrls.length > 1)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: _Pill(
                        icon: Icons.photo_library_outlined,
                        text: '${ad.imageUrls.length}',
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: pending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.hourglass_top, color: Colors.orange),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: MyAdActions(ad: ad),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ad.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              formatMoney(ad.price),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: videoPlayable
                  ? TextButton.icon(
                      style: _videoStyle,
                      onPressed: () => onOpenVideo(context, c),
                      icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                      label: Text(context.tr('link_video_open'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )
                  : videoPending
                      ? TextButton.icon(
                          style: _videoStyle,
                          onPressed: null,
                          icon: const Icon(Icons.hourglass_top, size: 18),
                          label: Text(context.tr('jobs_status_pending'),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )
                      : TextButton.icon(
                          style: _videoStyle,
                          onPressed: () => onAddVideo(context, ad),
                          icon: const Icon(Icons.videocam_outlined, size: 18),
                          label: Text(context.tr('my_shop_video_add'),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  static final _videoStyle = TextButton.styleFrom(
    minimumSize: const Size(48, 36),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.centerLeft,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
