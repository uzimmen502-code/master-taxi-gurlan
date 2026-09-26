import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/search_index_entry.dart';
import '../../../repositories/search_index_repository.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import 'ava_chip.dart';
import 'home_search_kind.dart';

/// Қидирув натижаси — индекс ёзуви ёки видео клип.
///
/// Видео `search_index` да ЙЎҚ (уни у ерга ёзадиган Cloud Function
/// йўқ), шунинг учун клиплар `tv_clips` дан бевосита қидирилади ва шу
/// ерда бирлаштирилади. Сервер ўзгариши талаб қилинмайди.
class HomeSearchHit {
  const HomeSearchHit.entry(this.entry)
      : clip = null,
        kind = null;

  HomeSearchHit.video(TvClip this.clip)
      : entry = null,
        kind = HomeSearchKind.video;

  final SearchIndexEntry? entry;
  final TvClip? clip;
  final HomeSearchKind? kind;

  HomeSearchKind get type => kind ?? homeSearchKindOf(entry!);

  String get title => entry?.title ?? clip!.title;

  String get subtitle =>
      entry?.subtitle ?? clip!.districtLabel;

  int? get price {
    if (entry != null) return entry!.price;
    return clip!.hasPrice ? clip!.price : null;
  }

  String get imageUrl => entry?.imageUrl ?? clip!.posterUrl;
}

/// 0-бўлим: «AVA'дан қидириш».
///
/// Натижаларда тур белгиси бор: Эълон · Хизмат · Маҳсулот · Видео.
class HomeGlobalSearchBar extends StatefulWidget {
  const HomeGlobalSearchBar({
    super.key,
    required this.onOpenEntry,
    required this.onOpenClip,
  });

  final Future<void> Function(SearchIndexEntry entry) onOpenEntry;
  final Future<void> Function(TvClip clip) onOpenClip;

  @override
  State<HomeGlobalSearchBar> createState() => _HomeGlobalSearchBarState();
}

class _HomeGlobalSearchBarState extends State<HomeGlobalSearchBar> {
  final _repo = SearchIndexRepository();
  final _clips = TvClipsRepository();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  bool _loading = false;
  List<HomeSearchHit> _results = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_repo.fetchActiveCached());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // тозалаш тугмаси дарҳол пайдо бўлсин
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(v));
    });
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _query = q;
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
    });
    try {
      // Иккита манба параллел — бири йиқилса иккинчиси барибир чиқади.
      final results = await Future.wait<List<HomeSearchHit>>([
        _repo
            .search(q, limit: 30)
            .then((l) => l.map(HomeSearchHit.entry).toList())
            .catchError((_) => <HomeSearchHit>[]),
        _clips
            .searchByTitle(
              query: q,
              districtId: ServiceConfigHolder.districtId,
              limit: 6,
            )
            .then((l) => l.map(HomeSearchHit.video).toList())
            .catchError((_) => <HomeSearchHit>[]),
      ]);
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _results = [...results[0], ...results[1]];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _query = '';
      _results = const [];
      _loading = false;
    });
  }

  Future<void> _open(HomeSearchHit hit) async {
    if (hit.clip != null) {
      await widget.onOpenClip(hit.clip!);
    } else {
      await widget.onOpenEntry(hit.entry!);
    }
    if (mounted) _clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final showPanel = _query.length >= 2;
    final empty = _ctrl.text.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AvaRadius.search),
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  style: AvaText.body.copyWith(color: c.ink),
                  decoration: InputDecoration(
                    hintText: context.tr('home_search_hint'),
                    suffixIcon: empty
                        ? null
                        : IconButton(
                            tooltip: context.tr('home_search_clear'),
                            onPressed: _clear,
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: c.ink3),
                          ),
                    filled: false,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              Material(
                color: c.accentLime,
                child: InkWell(
                  onTap: () => _onChanged(_ctrl.text),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Icon(Icons.search_rounded,
                        size: 18, color: c.accentLimeInk),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showPanel) ...[
          const SizedBox(height: AvaSpace.gap),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AvaRadius.card),
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                : _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          context
                              .tr('home_search_empty')
                              .replaceAll('{query}', _query),
                          textAlign: TextAlign.center,
                          style: AvaText.caption.copyWith(color: c.ink2),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: c.line),
                        itemBuilder: (context, i) => _ResultRow(
                          hit: _results[i],
                          onTap: () => _open(_results[i]),
                        ),
                      ),
          ),
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onTap});

  final HomeSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final price = hit.price;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AvaTap.minSize),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _Thumb(hit: hit),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AvaText.productName.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 4),
                    // Тур белгиси — тавсиф талаби.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AvaChip(
                          label: hit.type.label(context),
                          icon: hit.type.icon,
                          tone: AvaChipTone.brand,
                        ),
                        if (hit.subtitle.isNotEmpty)
                          Text(
                            hit.subtitle,
                            style: AvaText.caption.copyWith(color: c.ink3),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (price != null && price > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${formatPrice(price)} $kCurrencySum',
                  style: AvaText.price.copyWith(color: c.brand),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.hit});

  final HomeSearchHit hit;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final url = hit.imageUrl.trim();

    Widget fallback() => Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(AvaRadius.card - 4),
          ),
          child: Icon(hit.type.icon, color: c.ink3, size: 20),
        );

    if (!url.startsWith('http')) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AvaRadius.card - 4),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => fallback(),
      ),
    );
  }
}
