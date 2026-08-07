import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/search_index_entry.dart';
import '../../../repositories/search_index_repository.dart';

/// Асосий экран: глобал қидирув («Тавсия этамиз»дан олдин).
class HomeGlobalSearchBar extends StatefulWidget {
  const HomeGlobalSearchBar({
    super.key,
    required this.onOpenEntry,
  });

  final Future<void> Function(SearchIndexEntry entry) onOpenEntry;

  @override
  State<HomeGlobalSearchBar> createState() => _HomeGlobalSearchBarState();
}

class _HomeGlobalSearchBarState extends State<HomeGlobalSearchBar> {
  final _repo = SearchIndexRepository();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  List<SearchIndexEntry> _results = const [];
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
      final list = await _repo.search(q, limit: 36);
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _results = list;
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

  IconData _iconFor(SearchIndexEntry e) {
    switch (e.iconKey) {
      case 'taxi':
        return Icons.local_taxi_outlined;
      case 'shop':
        return Icons.storefront_outlined;
      case 'job':
        return Icons.work_outline;
      case 'food':
        return Icons.restaurant_outlined;
      case 'bread':
        return Icons.bakery_dining_outlined;
      case 'yuk':
        return Icons.local_shipping_outlined;
      case 'milk':
        return Icons.water_drop_outlined;
      case 'oil':
        return Icons.oil_barrel_outlined;
      case 'carpet':
        return Icons.cleaning_services_outlined;
      case 'sell':
        return Icons.sell_outlined;
      default:
        return Icons.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPanel = _query.length >= 2;
    final fieldEmpty = _ctrl.text.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              // Пастки чуқурлик — лайм фондан ажралиб туради
              BoxShadow(
                color: AppColors.limeDeep.withValues(alpha: 0.28),
                offset: const Offset(0, 3),
                blurRadius: 8,
                spreadRadius: 0,
              ),
              // Юқори енгил «ёруғлик» — 3D рельеф
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.85),
                offset: const Offset(0, -1),
                blurRadius: 2,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            elevation: 0,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: (v) {
                setState(() {}); // «Қидирув:» дарҳол яширилади
                _onChanged(v);
              },
              textInputAction: TextInputAction.search,
              cursorHeight: 18,
              cursorColor: AppColors.limeDeep,
              style: const TextStyle(
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B2E0A),
              ),
              decoration: InputDecoration(
                // Бўш: лупа + «Қидирув:» тўқ + мисоллар хира. Ёзилганда фақат матн.
                hintText: fieldEmpty ? 'такси, нон, иш, Лабо…' : null,
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                // prefix эмас — Row: баъзи Flutter версияларида prefix яширинади.
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search,
                        size: 26,
                        color: AppColors.limeDeep,
                      ),
                      if (fieldEmpty) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Қидирув:',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: AppColors.limeDeep,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: fieldEmpty ? 118 : 44,
                  minHeight: 42,
                ),
                suffixIcon: fieldEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Тозалаш',
                        onPressed: _clear,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.clear,
                          size: 18,
                          color: AppColors.sectionMuted.withValues(alpha: 0.9),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 42,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.limeDeep,
                    width: 1.4,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.limeDeep,
                    width: 1.4,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.limeDeep,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showPanel) ...[
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: 2,
            shadowColor: Colors.black26,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            '«$_query» бўйича топилмади',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                          ),
                          itemBuilder: (context, i) {
                            final e = _results[i];
                            return ListTile(
                              dense: true,
                              leading: _Thumb(entry: e, icon: _iconFor(e)),
                              title: Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (e.subtitle.isNotEmpty) e.subtitle,
                                  if (e.price != null && e.price! > 0)
                                    '${formatPrice(e.price!)} сўм',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Text(
                                e.type == SearchIndexEntry.typeService ||
                                        e.type ==
                                            SearchIndexEntry.typeIntercityRoute
                                    ? 'ОЧИШ'
                                    : 'КЎРИШ',
                                style: TextStyle(
                                  color: AppColors.button,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () async {
                                await widget.onOpenEntry(e);
                                if (mounted) _clear();
                              },
                            );
                          },
                        ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.entry, required this.icon});

  final SearchIndexEntry entry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final url = entry.imageUrl.trim();
    if (url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _iconBox(),
        ),
      );
    }
    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7E8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppColors.button, size: 22),
    );
  }
}
