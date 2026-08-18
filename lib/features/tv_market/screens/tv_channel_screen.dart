import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_public_profiles_repository.dart';
import '../services/tv_clip_delete.dart';
import '../utils/tv_highlight_order.dart';
import '../utils/tv_view_format.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_channel_header.dart';
import '../widgets/tv_clip_poster.dart';
import 'tv_market_feed_screen.dart';
import 'tv_publish_screen.dart';

/// Doʻkonsiz nashriyotchi kanali — roliklar grid + qoʻngʻiroq.
class TvChannelScreen extends StatefulWidget {
  const TvChannelScreen({
    super.key,
    required this.ownerPhone,
    this.ownerDisplayName = '',
    this.districtLabel = '',
    this.highlightClipId = '',
    this.isOwner = false,
  });

  final String ownerPhone;
  final String ownerDisplayName;
  final String districtLabel;
  final String highlightClipId;
  final bool isOwner;

  @override
  State<TvChannelScreen> createState() => _TvChannelScreenState();
}

class _TvChannelScreenState extends State<TvChannelScreen> {
  final _clipsRepo = TvClipsRepository();
  final _profilesRepo = TvPublicProfilesRepository();
  List<TvClip> _clips = const [];
  String _displayName = '';
  String _district = '';
  int _totalViewCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _displayName = tvOwnerDisplayName(widget.ownerDisplayName);
    _district = widget.districtLabel.trim();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _clipsRepo.fetchByOwner(widget.ownerPhone);
      final active = list.where((c) => c.isActive).toList();
      final sorted = tvOrderHighlightFirst(
        active,
        (c) => c.id == widget.highlightClipId,
      );
      if (_displayName.isEmpty) {
        final names = await _profilesRepo.fetchMany([widget.ownerPhone]);
        final id = canonicalPhoneId(widget.ownerPhone);
        _displayName = tvOwnerDisplayName(names[id] ?? '');
      }
      if (_district.isEmpty && sorted.isNotEmpty) {
        _district = sorted.first.districtLabel.trim();
      }
      final totalViews =
          await _profilesRepo.fetchTotalViewCount(widget.ownerPhone);
      if (!mounted) return;
      setState(() {
        _clips = sorted;
        _totalViewCount = totalViews;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvChannel] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _call() async {
    final ok = await callPhone(widget.ownerPhone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openClip(TvClip clip) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    );
  }

  Future<void> _publish() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TvPublishScreen()),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _edit(TvClip clip) async {
    final updated = await Navigator.push<TvClip>(
      context,
      MaterialPageRoute(builder: (_) => TvPublishScreen(editClip: clip)),
    );
    if (updated != null && mounted) await _load();
  }

  Future<void> _delete(TvClip clip) async {
    final ok = await confirmDeleteTvClip(context, clip);
    if (ok && mounted) await _load();
  }

  String get _title {
    if (_displayName.isNotEmpty) return _displayName;
    return context.tr('tv_channel_title');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.4,
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: _publish,
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.videocam_rounded),
              label: Text(
                context.tr('tv_channel_publish'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clips.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      context.tr('tv_market_no_clips'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      sliver: SliverToBoxAdapter(
                        child: TvChannelHeader(
                          displayName: _displayName,
                          districtLabel: _district,
                          clipCount: _clips.length,
                          totalViewCount: _totalViewCount,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          context.tr('tv_channel_clips'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final clip = _clips[i];
                            final hi = clip.id == widget.highlightClipId;
                            return _ClipTile(
                              clip: clip,
                              highlight: hi,
                              showOwnerMenu: widget.isOwner,
                              onTap: () => _openClip(clip),
                              onEdit: () => _edit(clip),
                              onDelete: () => _delete(clip),
                            );
                          },
                          childCount: _clips.length,
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar:
          widget.isOwner ? null : TvChannelContactBar(onCall: _call),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.clip,
    required this.highlight,
    required this.showOwnerMenu,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final TvClip clip;
  final bool highlight;
  final bool showOwnerMenu;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: highlight
                  ? const Color(0xFF00E676)
                  : Colors.grey.shade200,
              width: highlight ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TvClipPoster(url: clip.posterUrl),
                    if (highlight)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.tr('tv_channel_from_reel'),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    if (showOwnerMenu)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 20,
                            ),
                            onSelected: (v) {
                              if (v == 'edit') onEdit();
                              if (v == 'delete') onDelete();
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(ctx.tr('tv_market_edit')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(ctx.tr('tv_market_delete')),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (clip.hasPrice)
                      Text(
                        formatMoney(clip.price),
                        style: const TextStyle(
                          color: Color(0xFF00A853),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    if (clip.viewCount > 0)
                      Row(
                        children: [
                          Icon(Icons.visibility_outlined,
                              size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 3),
                          Text(
                            tvFormatViewCount(clip.viewCount),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
