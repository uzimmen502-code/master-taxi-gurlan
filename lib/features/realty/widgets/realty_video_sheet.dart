import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/screens/tv_market_feed_screen.dart';
import '../realty_tabs.dart';

/// Объектга боғланган видеони очиш.
///
/// Мавжуд AVAGram плеери қайта ишлатилади — кўчмас мулк учун алоҳида
/// видео ўйнатгич қурилмайди.
Future<void> openRealtyVideo(
  BuildContext context, {
  required String clipId,
}) async {
  final snap =
      await FirebaseFirestore.instance.collection('tv_clips').doc(clipId).get();
  if (!context.mounted) return;
  if (!snap.exists) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('realty_video_missing')),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final clip = TvClip.fromFirestore(snap);
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
  );
}

/// Эга ўз AVAGram видеоларидан бирини объектга боғлайди.
///
/// Концепциянинг 3-бўлими: боғлаш ИХТИЁРИЙ. Боғланмаса эълон
/// тугмасиз, одатдагидек кўринади.
Future<bool> showRealtyVideoSheet(
  BuildContext context, {
  required RealtyListing listing,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VideoSheet(listing: listing),
  );
  return changed == true;
}

class _VideoSheet extends StatefulWidget {
  const _VideoSheet({required this.listing});

  final RealtyListing listing;

  @override
  State<_VideoSheet> createState() => _VideoSheetState();
}

class _VideoSheetState extends State<_VideoSheet> {
  final _repo = RealtyRepository();
  final _clips = TvClipsRepository();

  List<TvClip> _items = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = canonicalPhoneId(
      // Эганинг рақами — клиплар шу бўйича сақланган.
      await _repo.myOwnerPhone(),
    );
    final clips = phone.isEmpty
        ? const <TvClip>[]
        : await _clips.fetchByOwner(phone);
    if (!mounted) return;
    setState(() {
      _items = clips.where((c) => c.status == 'active').toList();
      _loading = false;
    });
  }

  Future<void> _link(TvClip clip) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _repo.linkVideo(
        listingId: widget.listing.id,
        clipId: clip.id,
      );
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_video_linked')),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.plain),
        behavior: SnackBarBehavior.floating,
      ));
    } on RealtyException {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_error_generic')),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _unlink() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await _repo.unlinkVideo(widget.listing.id);
      if (mounted) navigator.pop(true);
    } on RealtyException {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      top: false,
      child: Material(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr('realty_video_title'),
                      style: TextStyle(
                        fontSize: AppText.titleMedium,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('realty_video_body'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppText.bodySmall,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.listing.hasVideo)
                TextButton.icon(
                  onPressed: _busy ? null : _unlink,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: Text(context.tr('realty_video_unlink')),
                  style: TextButton.styleFrom(
                    foregroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
                  ),
                ),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              context.tr('realty_video_empty'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.ink2),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final clip = _items[i];
                              final linked =
                                  widget.listing.videoClipId == clip.id;
                              return ListTile(
                                leading: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: clip.posterUrl.isEmpty
                                      ? Icon(
                                          Icons.videocam_outlined,
                                          color: c.ink3,
                                        )
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            clip.posterUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(color: c.surface2),
                                          ),
                                        ),
                                ),
                                title: Text(
                                  clip.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  context.tr(
                                    clip.category == 'ad'
                                        ? 'realty_video_paid'
                                        : 'realty_video_free',
                                  ),
                                  style: TextStyle(
                                    fontSize: AppText.labelTiny,
                                    color: c.ink3,
                                  ),
                                ),
                                trailing: linked
                                    ? Icon(Icons.check_circle, color: c.brand)
                                    : null,
                                onTap: _busy ? null : () => _link(clip),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
