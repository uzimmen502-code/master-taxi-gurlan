import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/geo/geo_tier_bar.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../jobs_colors.dart';
import '../jobs_sections.dart';
import '../controllers/jobs_controller.dart';
import '../widgets/ad_card.dart';
import '../widgets/add_ad_sheet.dart';
import 'jobs_my_ads_screen.dart';

/// `jobs` модулининг БИТТА бўлими — «Эълонлар» ёки «Хизматлар».
///
/// Аввал битта экранда 2 таб эди; эга қарори (2026-10-06) бўйича энди
/// ҳар бўлим ўз плиткасидан табсиз очилади ва ўз рангига эга
/// (қаранг: [JobsSections]).
class JobsScreen extends StatelessWidget {
  const JobsScreen({
    super.key,
    this.kind = AdKind.ad,
    this.openAddSheet = false,
    this.highlightAdId = '',
  });

  /// [AdKind.ad] — «Эълонлар», [AdKind.service] — «Хизматлар».
  /// Эски [AdKind.work] «Эълонлар»га тушади.
  final AdKind kind;

  /// Экран очилиши билан «янги эълон» варақасини очиш — бош саҳифадаги
  /// «＋» менюсидан келганда, фойдаланувчи яна бир марта босмаслиги учун.
  final bool openAddSheet;

  /// Бош саҳифадаги қатордан келинганда — АЙНАН ўша эълоннинг `id`си.
  ///
  /// Ўша эълон рўйхатнинг ТЕПАСИГА чиқарилади ва ажратиб кўрсатилади.
  /// Нега шундай: бу экранда эълоннинг ўз тафсилот саҳифаси йўқ —
  /// карточканинг ўзи тўлиқ маълумот (матн, нарх, телефон, «Қўнғироқ»).
  /// Шунинг учун «очиш» = ўша карточкани дарҳол кўз олдига чиқариш.
  /// Аввал бу ерда ҳеч нарса узатилмасди ва фойдаланувчи босган эълонини
  /// умумий рўйхатдан қайтадан қидирарди.
  final String highlightAdId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => JobsController(repo: ctx.read<JobsRepository>()),
      child: _JobsView(
        kind: JobsSections.sectionOf(kind),
        openAddSheet: openAddSheet,
        highlightAdId: highlightAdId,
      ),
    );
  }
}

/// [highlightAdId] рўйхат тепасига кўчирилган нусхани қайтаради.
///
/// Сof функция — виджетсиз тестланади. Эълон топилмаса (муддати тугаган,
/// ўчирилган ёки бошқа табда) рўйхат ЎЗГАРМАЙДИ.
List<JobAd> jobsFeedWithHighlightFirst(List<JobAd> feed, String highlightId) {
  if (highlightId.isEmpty) return feed;
  final i = feed.indexWhere((a) => a.id == highlightId);
  if (i <= 0) return feed;
  return [feed[i], ...feed.take(i), ...feed.skip(i + 1)];
}

class _JobsView extends StatefulWidget {
  const _JobsView({
    required this.kind,
    this.openAddSheet = false,
    this.highlightAdId = '',
  });

  final AdKind kind;
  final bool openAddSheet;
  final String highlightAdId;

  @override
  State<_JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<_JobsView> {
  final _searchCtrl = TextEditingController();

  /// Эгалари ўз эълонига қўшган видео: `эълон id → клип`. Битта сўров
  /// (`TvClipLink`); эгалик карточка томонида текширилади.
  Map<String, TvClip> _linked = const {};

  Future<void> _loadLinked() async {
    try {
      final repo = TvClipsRepository();
      final r = await Future.wait([
        repo.fetchLinkedMap(TvClipLink.kindAd),
        repo.fetchLinkedMap(TvClipLink.kindService),
      ]);
      if (!mounted) return;
      setState(() => _linked = {...r[0], ...r[1]});
    } catch (_) {
      // Видео — қўшимча; юкланмаса рўйхат ишлайверади.
    }
  }

  void _onLinkChanged() => unawaited(_loadLinked());

  /// Карточка учун: клип эгаси = эълон эгаси бўлсагина.
  TvClip? _clipFor(JobAd ad) =>
      TvClipLink.ownedClip(_linked, ad.id, ad.authorPhone);

  /// Бўлим ранги — AppBar, қидирув, юкланиш (эга қарори: бўлимлар рангда
  /// фарқ қилсин).
  Color get _color => JobsColors.accentFor(widget.kind);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLinked());
    TvClipLink.changes.addListener(_onLinkChanged);
    if (widget.highlightAdId.isNotEmpty) {
      // Глобал қидирувдан келинган эълон бошқа ҳудудда бўлиши мумкин.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<JobsController>().showNationwideOnce();
      });
    }
    if (widget.openAddSheet) {
      // `JobsController` provider'и тайёр бўлгач — биринчи frame'дан кейин.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAddAdSheet();
      });
    }
  }

  @override
  void dispose() {
    TvClipLink.changes.removeListener(_onLinkChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    context.read<JobsController>().setSearch(v);
  }

  void _openAddAdSheet() {
    showAddAdSheet(
      context: context,
      controller: context.read<JobsController>(),
      presetKind: widget.kind,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    final color = _color;
    return Scaffold(
      backgroundColor: JobsColors.scaffold,
      appBar: AppBar(
        title: Text(
          context.tr(JobsSections.titleKeyFor(widget.kind)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        foregroundColor: JobsColors.onBar,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _openAddAdSheet,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    context.tr(JobsSections.addKeyFor(widget.kind)),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // Оқ фон + бўлим рангидаги матн; контур — дизайнга мос қизил.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(
                        color: Color(0xFFC62828),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: JobsColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          // «Менинг эълонларим» қидирув қаторида: AppBar'да катта шрифтда
          // сарлавҳани «Эъл…» га қисиб қўйган эди (қурилмада, 130% шрифт).
          // Текширувдаги/рад этилган эълонларни ҳам кўради (лента фақат фаол).
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(
                color: JobsColors.ink,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: context.tr('jobs_search_hint'),
                hintStyle: const TextStyle(
                    color: JobsColors.hint, fontSize: AppText.bodyMedium),
                prefixIcon: Icon(
                  Icons.search,
                  color: color,
                  size: 20,
                ),
                suffixIcon: c.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: JobsColors.muted, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          c.clearSearch();
                        })
                    : null,
                filled: true,
                fillColor: JobsColors.fieldFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            )),
            const SizedBox(width: 8),
            Tooltip(
              message: context.tr('jobs_my_ads'),
              child: Material(
                color: JobsColors.fieldFill,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => openJobsMyAds(context, c),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: JobsColors.border),
                    ),
                    child: Icon(Icons.assignment_ind_outlined, color: color),
                  ),
                ),
              ),
            ),
          ]),
        ),
        GeoTierBar(moduleId: 'jobs', scope: c.scope, onChanged: c.setScope),
        Expanded(
          child: _Feed(
            kindFilter: widget.kind,
            highlightAdId: widget.highlightAdId,
            color: color,
            clipFor: _clipFor,
          ),
        ),
      ]),
    );
  }
}

/// Бўлим рўйхати.
class _Feed extends StatelessWidget {
  const _Feed({
    required this.kindFilter,
    required this.color,
    required this.clipFor,
    this.highlightAdId = '',
  });

  final AdKind kindFilter;
  final Color color;
  final String highlightAdId;

  /// Эълон учун эгаси қўшган видео (эгалик текширилган) ёки `null`.
  final TvClip? Function(JobAd ad) clipFor;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    return StreamBuilder<List<JobAd>>(
      stream: c.watchAll(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Center(child: CircularProgressIndicator(color: color));
        }
        if (snap.hasError) {
          // Ички хато матни фойдаланувчига кўрсатилмайди (CLAUDE.md 25).
          debugPrint('[Jobs feed] ${snap.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ctx.tr('jobs_load_error'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: JobsColors.muted)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: c.reload,
                  child: Text(ctx.tr('home_section_retry')),
                ),
              ]),
            ),
          );
        }
        final all = snap.data ?? const <JobAd>[];
        // Қидирув бошланганда ажратиб кўрсатиш ўринсиз — фойдаланувчи
        // энди бошқа нарса қидиряпти.
        final highlight = c.searchQuery.isEmpty ? highlightAdId : '';
        final list = jobsFeedWithHighlightFirst(
          c.feedForTab(all, kind: kindFilter),
          highlight,
        );
        final wider = GeoWiderHint(
          moduleId: 'jobs',
          scope: c.scope,
          onChanged: c.setScope,
        );
        // Саҳифалаш (B7): қидирув юкланган эълонлар ичида; яна бор бўлса — тугма.
        final loadMore = c.canLoadMore
            ? _LoadMore(
                searching: c.searchQuery.isNotEmpty,
                onTap: c.loadMore,
              )
            : null;
        if (list.isEmpty) {
          return ListView(
            children: [
              _EmptyState(
                kind: kindFilter,
                isSearching: c.searchQuery.isNotEmpty,
              ),
              if (loadMore != null) loadMore,
              wider,
            ],
          );
        }
        // Ҳудудда кам — пастда кенгроқ ҳудуд таклифи (2-такомиллаштириш).
        final showWider = list.length < 5;
        final tail = (loadMore != null ? 1 : 0) + (showWider ? 1 : 0);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
          itemCount: list.length + tail,
          itemBuilder: (_, i) {
            if (i < list.length) {
              return AdCard(
                ad: list[i],
                highlighted: highlight.isNotEmpty && list[i].id == highlight,
                linkedClip: clipFor(list[i]),
              );
            }
            final extra = i - list.length;
            if (loadMore != null && extra == 0) return loadMore;
            return wider;
          },
        );
      },
    );
  }
}

/// «Яна юклаш» — рўйхат саҳифалаб юкланади (аввал ҳар очилишда 500 та
/// ҳужжат real-time тингланарди). Қидирув юкланган эълонлар ичида эканини
/// айтамиз, акс ҳолда одам "топилмади" деб ўйлайди.
class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.searching, required this.onTap});

  final bool searching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(children: [
        if (searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              context.tr('jobs_load_more_search'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: AppText.labelSmall, color: JobsColors.muted),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.expand_more),
          label: Text(context.tr('jobs_load_more')),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.kind,
    required this.isSearching,
  });

  final AdKind? kind;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final emoji = kind?.emoji ?? '📰';
    final label = context.tr(JobsSections.kindLabelKey(kind ?? AdKind.ad));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(
            context.tr(
                isSearching ? 'jobs_empty_search_title' : 'jobs_empty_title'),
            style: const TextStyle(
                fontSize: AppText.bodyLarge,
                fontWeight: FontWeight.w600,
                color: JobsColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching
                ? context.tr('jobs_empty_search_hint')
                : context.tr('jobs_empty_first').replaceAll('{label}', label),
            style: const TextStyle(
                fontSize: AppText.bodySmall, color: JobsColors.muted),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
