import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../widgets/tv_clip_poster.dart';
import 'tv_market_feed_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.fetchByOwner(widget.ownerPhone);
      if (!mounted) return;
      setState(() {
        _clips = list.where((c) => c.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvOwnerClips] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ownerName.trim().isEmpty
        ? context.tr('tv_market_owner_clips')
        : widget.ownerName;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
                              child: TvClipPoster(url: clip.posterUrl),
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
