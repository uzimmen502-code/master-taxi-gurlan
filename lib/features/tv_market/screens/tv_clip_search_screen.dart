import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../ads/utils/ad_search_text.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../widgets/tv_clip_poster.dart';

/// Ролик қидируви — CatalogSearch, 3 тил, қора экран.
class TvClipSearchScreen extends StatefulWidget {
  const TvClipSearchScreen({
    super.key,
    this.districtId = '',
    this.districtLabel = '',
  });

  final String districtId;
  final String districtLabel;

  @override
  State<TvClipSearchScreen> createState() => _TvClipSearchScreenState();
}

class _TvClipSearchScreenState extends State<TvClipSearchScreen> {
  static const _lime = Color(0xFF00E676);

  final _repo = TvClipsRepository();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<TvClip> _hits = const [];
  bool _loading = false;
  bool _error = false;
  bool _allDistricts = false;
  String _lastQuery = '';

  bool get _districtScoped =>
      widget.districtId.isNotEmpty && !_allDistricts;

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
        _error = false;
        _lastQuery = q;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    _debounce = Timer(const Duration(milliseconds: 220), () => _run(q));
  }

  Future<void> _run(String q) async {
    try {
      final list = await _repo.searchByTitle(
        query: q,
        districtId: _districtScoped ? widget.districtId : '',
      );
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _hits = list;
        _loading = false;
        _error = false;
        _lastQuery = q;
      });
    } catch (e) {
      debugPrint('[TvClipSearch] $e');
      if (mounted && _ctrl.text.trim() == q) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _expandDistricts() {
    setState(() => _allDistricts = true);
    final q = _ctrl.text.trim();
    if (q.length >= 2) {
      setState(() => _loading = true);
      unawaited(_run(q));
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
          cursorColor: _lime,
          decoration: InputDecoration(
            hintText: context.tr('tv_market_search_hint'),
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
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
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(
            minHeight: 2,
            color: _lime,
            backgroundColor: Color(0xFF222222),
          ),
          if (_districtScoped || (_lastQuery.length >= 2 && !_loading && !_error))
            _buildMetaBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildMetaBar() {
    final scoped = _districtScoped;
    final label = widget.districtLabel.trim();
    final showCount =
        _lastQuery.length >= 2 && !_loading && !_error && _hits.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: scoped && label.isNotEmpty
                ? Text(
                    context
                        .tr('tv_market_search_in_district')
                        .replaceAll('{district}', label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (showCount)
            Text(
              context
                  .tr('tv_market_search_count')
                  .replaceAll('{n}', '${_hits.length}'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_ctrl.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            context.tr('tv_market_search_empty'),
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
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('tv_market_search_error'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  final q = _ctrl.text.trim();
                  setState(() => _loading = true);
                  unawaited(_run(q));
                },
                child: Text(context.tr('tv_market_search_retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading && _hits.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
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
              if (_districtScoped) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _expandDistricts,
                  child: Text(
                    context.tr('tv_market_search_all_districts'),
                    style: const TextStyle(
                      color: _lime,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) _focus.unfocus();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.68,
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
                        _HighlightTitle(text: clip.title, query: _lastQuery),
                        if (clip.hasPrice)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              formatMoney(clip.price),
                              style: const TextStyle(
                                color: _lime,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (clip.districtLabel.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              clip.districtLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
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
      ),
    );
  }
}

class _HighlightTitle extends StatelessWidget {
  const _HighlightTitle({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final base = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    final hit = base.copyWith(color: const Color(0xFF00E676));
    final q = query.trim();
    if (q.length < 2) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
    }
    final needles = <String>{
      q,
      AdSearchText.toLatin(q),
      AdSearchText.toCyrillic(q),
    }.where((s) => s.length >= 2);
    final lower = text.toLowerCase();
    var start = -1;
    var len = 0;
    for (final n in needles) {
      final i = lower.indexOf(n.toLowerCase());
      if (i >= 0) {
        start = i;
        len = n.length;
        break;
      }
    }
    if (start < 0 || start + len > text.length) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
    }
    final end = start + len;
    return Text.rich(
      TextSpan(
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start), style: base),
          TextSpan(text: text.substring(start, end), style: hit),
          if (end < text.length)
            TextSpan(text: text.substring(end), style: base),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
