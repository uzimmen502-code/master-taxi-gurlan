import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../widgets/tv_clip_poster.dart';

/// Сарлавҳа бўйича ролик қидируви — қора экран, натижадан лентага қайтади.
class TvClipSearchScreen extends StatefulWidget {
  const TvClipSearchScreen({super.key, this.districtId = ''});

  final String districtId;

  @override
  State<TvClipSearchScreen> createState() => _TvClipSearchScreenState();
}

class _TvClipSearchScreenState extends State<TvClipSearchScreen> {
  final _repo = TvClipsRepository();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<TvClip> _hits = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _hits = const [];
        _loading = false;
        _lastQuery = q;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 280), () => _run(q));
  }

  Future<void> _run(String q) async {
    try {
      final list = await _repo.searchByTitle(
        query: q,
        districtId: widget.districtId,
      );
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _hits = list;
        _loading = false;
        _lastQuery = q;
      });
    } catch (e) {
      debugPrint('[TvClipSearch] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          cursorColor: const Color(0xFF00E676),
          decoration: InputDecoration(
            hintText: context.tr('tv_market_search_hint'),
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w500,
            ),
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('tv_market_search_clear'),
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                      _focus.requestFocus();
                    },
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
          ),
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            unawaited(_run(v.trim()));
          },
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_ctrl.text.trim().length < 2) {
      return Center(
        child: Text(
          context.tr('tv_market_search_empty'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            context
                .tr('tv_market_search_none')
                .replaceAll('{query}', _lastQuery),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: _hits.length,
      itemBuilder: (context, i) {
        final clip = _hits[i];
        return Material(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.pop(context, clip),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: TvClipPoster(url: clip.posterUrl)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (clip.hasPrice)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            formatMoney(clip.price),
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
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
    );
  }
}
