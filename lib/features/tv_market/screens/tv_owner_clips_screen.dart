import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../services/tv_clip_delete.dart';
import '../widgets/tv_clip_poster.dart';
import 'tv_market_feed_screen.dart';
import 'tv_publish_screen.dart';

/// Сотувчининг ролик рўйхати (дўкон ҳали йўқ бўлса).
class TvOwnerClipsScreen extends StatefulWidget {
  const TvOwnerClipsScreen({
    super.key,
    required this.ownerPhone,
    required this.ownerName,
  });

  final String ownerPhone;
  final String ownerName;

  @override
  State<TvOwnerClipsScreen> createState() => _TvOwnerClipsScreenState();
}

class _TvOwnerClipsScreenState extends State<TvOwnerClipsScreen> {
  final _repo = TvClipsRepository();
  List<TvClip> _clips = const [];
  bool _loading = true;
  String _mePhone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isMine => phonesMatch(widget.ownerPhone, _mePhone);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await _repo.fetchByOwner(widget.ownerPhone);
      if (!mounted) return;
      setState(() {
        _mePhone = phoneDigits(prefs.getString('user_phone') ?? '');
        _clips = list.where((c) => c.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvOwnerClips] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(TvClip clip) async {
    final updated = await Navigator.push<TvClip>(
      context,
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(editClip: clip),
      ),
    );
    if (updated != null && mounted) await _load();
  }

  Future<void> _delete(TvClip clip) async {
    final ok = await confirmDeleteTvClip(context, clip);
    if (ok && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ownerName.trim().isEmpty
        ? context.tr('tv_market_owner_clips')
        : widget.ownerName;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0.4,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clips.isEmpty
              ? Center(
                  child: Text(
                    context.tr('tv_market_no_clips'),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _clips.length,
                  itemBuilder: (context, i) {
                    final clip = _clips[i];
                    return Material(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TvMarketFeedScreen(initialClip: clip),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  TvClipPoster(url: clip.posterUrl),
                                  if (_isMine)
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
                                            if (v == 'edit') _edit(clip);
                                            if (v == 'delete') _delete(clip);
                                          },
                                          itemBuilder: (ctx) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text(
                                                ctx.tr('tv_market_edit'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                ctx.tr('tv_market_delete'),
                                              ),
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
