import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../jobs_colors.dart';
import '../jobs_tabs.dart';
import '../controllers/jobs_controller.dart';
import '../widgets/ad_card.dart';
import '../widgets/add_ad_sheet.dart';

/// ИШ ЭЪЛОН — 2 таб: Иш бор, Хизмат таклифи.
class JobsScreen extends StatelessWidget {
  const JobsScreen({
    super.key,
    this.initialTabIndex = JobsTabs.ad,
    this.openAddSheet = false,
    this.highlightAdId = '',
  });

  /// [JobsTabs.ad], [JobsTabs.service].
  final int initialTabIndex;

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
        initialTabIndex: initialTabIndex,
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
    required this.initialTabIndex,
    this.openAddSheet = false,
    this.highlightAdId = '',
  });

  final int initialTabIndex;
  final bool openAddSheet;
  final String highlightAdId;

  @override
  State<_JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<_JobsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final start = JobsTabs.clampIndex(widget.initialTabIndex);
    _tabCtrl = TabController(length: JobsTabs.count, vsync: this, initialIndex: start);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.openAddSheet) {
      // `JobsController` provider'и тайёр бўлгач — биринчи frame'дан кейин.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAddAdSheet();
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    context.read<JobsController>().setSearch(v);
  }

  AdKind? _kindForCurrentTab() {
    // Свайп анимацияси давомида эски индекс қолмасин.
    if (_tabCtrl.indexIsChanging) {
      return JobsTabs.kindForIndex(_tabCtrl.animation?.value.round()
              ?? _tabCtrl.index);
    }
    return JobsTabs.kindForIndex(_tabCtrl.index);
  }

  void _openAddAdSheet() {
    showAddAdSheet(
      context: context,
      controller: context.read<JobsController>(),
      presetKind: _kindForCurrentTab(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    return Scaffold(
      backgroundColor: JobsColors.scaffold,
      appBar: AppBar(
        title: Text(
          context.tr('home_module_jobs'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: JobsColors.bar,
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
                  label: const Text(
                    'Эълон қўшиш',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // Оқ фон + кўк матн; контур — дизайнга мос қизил.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: JobsColors.accentBlue,
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: JobsColors.bar,
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              indicatorColor: JobsColors.onBar,
              indicatorWeight: 3,
              labelColor: JobsColors.onBar,
              unselectedLabelColor: JobsColors.tabUnselected,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: AppText.bodyLarge),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: AppText.bodyLarge),
              tabs: JobsTabs.labels
                  .map((label) => Tab(text: label))
                  .toList(growable: false),
            ),
          ),
        ),
      ),
      body: Column(children: [
        Container(
          color: JobsColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(
              color: JobsColors.ink,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Қидириш... (масалан: ҳайдовчи, тозалаш)',
              hintStyle: const TextStyle(
                  color: JobsColors.hint, fontSize: AppText.bodyMedium),
              prefixIcon: const Icon(
                Icons.search,
                color: JobsColors.bar,
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
                  borderSide:
                      const BorderSide(color: JobsColors.bar, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _Feed(
                kindFilter: AdKind.ad,
                highlightAdId: widget.highlightAdId,
              ),
              _Feed(
                kindFilter: AdKind.service,
                highlightAdId: widget.highlightAdId,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Битта таб контенти.
class _Feed extends StatelessWidget {
  const _Feed({this.kindFilter, this.highlightAdId = ''});

  final AdKind? kindFilter;
  final String highlightAdId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    return StreamBuilder<List<JobAd>>(
      stream: c.watchAll(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: JobsColors.bar));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Хатолик: ${snap.error}',
                  style: const TextStyle(color: JobsColors.muted)),
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
        if (list.isEmpty) {
          return _EmptyState(
            kind: kindFilter,
            isSearching: c.searchQuery.isNotEmpty,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
          itemCount: list.length,
          itemBuilder: (_, i) => AdCard(
            ad: list[i],
            highlighted: highlight.isNotEmpty && list[i].id == highlight,
          ),
        );
      },
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
    final label = kind?.label ?? 'Эълон';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              Text(
                isSearching ? 'Натижа топилмади' : 'Ҳозирча эълон йўқ',
                style: const TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: JobsColors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                isSearching
                    ? 'Қидирув матнини ўзгартиринг'
                    : 'Биринчи бўлиб «$label» қўшинг!',
                style: const TextStyle(
                    fontSize: AppText.bodySmall,
                    color: JobsColors.muted),
                textAlign: TextAlign.center,
              ),
            ]),
      ),
    );
  }
}
