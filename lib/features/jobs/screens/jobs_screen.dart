import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../utils/app_theme.dart';
import '../controllers/jobs_controller.dart';
import '../widgets/ad_card.dart';
import '../widgets/add_ad_sheet.dart';
import '../widgets/complaint_sheet.dart';
import '../widgets/edit_ad_sheet.dart';

/// 📰 ИШ ТОП экрани — mini-OLX classifieds.
///
/// 4 та таб:
///   • 🆕 Барчаси  — барча эълонлар (latest first)
///   • 🔨 Иш      — иш топувчилар учун
///   • 🛠️ Хизмат   — хизмат таклифлари
///   • 📢 Эълон    — оддий эълонлар (сотиш / шарт)
class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => JobsController(repo: ctx.read<JobsRepository>()),
      child: const _JobsView(),
    );
  }
}

class _JobsView extends StatefulWidget {
  const _JobsView();

  @override
  State<_JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends State<_JobsView>
    with SingleTickerProviderStateMixin {
  static const _brand = Color(0xFF0277BD);

  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
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

  Future<void> _onComplaintTap(JobAd ad) async {
    final c = context.read<JobsController>();
    final reason = await showComplaintSheet(context);
    if (reason == null || !mounted) return;
    await c.submitComplaint(adId: ad.id, reason: reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Шикоят юборилди'),
      backgroundColor: _brand,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  AdKind? _kindForCurrentTab() {
    switch (_tabCtrl.index) {
      case 1:
        return AdKind.work;
      case 2:
        return AdKind.service;
      case 3:
        return AdKind.ad;
      default:
        return null; // barchasi
    }
  }

  void _openAddAdSheet() {
    final preset = _kindForCurrentTab();
    showAddAdSheet(
      context: context,
      controller: context.read<JobsController>(),
      presetKind: preset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('📰 ИШ ТОП',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _openAddAdSheet,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text(
                    'Эълон қўшиш',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF013F67),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Colors.white24),
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
            color: _brand,
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: false,
              tabAlignment: TabAlignment.fill,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppText.bodyLarge),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppText.bodyLarge),
              tabs: const [
                Tab(text: 'Барчаси'),
                Tab(text: 'Иш'),
                Tab(text: 'Хизмат'),
                Tab(text: 'Эълон'),
              ],
            ),
          ),
        ),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Қидириш... (масалан: сотилади, шоли)',
              hintStyle: TextStyle(
                  color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
              prefixIcon:
                  const Icon(Icons.search, color: _brand, size: 20),
              suffixIcon: c.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.grey, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        c.clearSearch();
                      })
                  : null,
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _brand, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _Feed(kindFilter: null),
              _Feed(kindFilter: AdKind.work),
              _Feed(kindFilter: AdKind.service),
              _Feed(kindFilter: AdKind.ad),
            ],
          ),
        ),
      ]),
    );
  }

  void _onAdTapEdit(JobAd ad) {
    showEditAdSheet(
        context: context, ad: ad, controller: context.read<JobsController>());
  }
}

/// Битта таб контенти — стрим + filterAndSort + UI.
class _Feed extends StatelessWidget {
  const _Feed({required this.kindFilter});

  /// `null` бўлса барча 3 турни кўрсатади.
  final AdKind? kindFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    final state = context.findAncestorStateOfType<_JobsViewState>();
    return StreamBuilder<List<JobAd>>(
      stream: c.watchAll(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0277BD)));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Хатолик: ${snap.error}',
                  style: TextStyle(color: Colors.grey.shade500)),
            ),
          );
        }
        final all = snap.data ?? const <JobAd>[];
        // Фильтрни client тарафда қилaмиз — server'да 3 та whereIn энг яхши.
        final filtered = kindFilter == null
            ? all
            : all.where((a) => a.kind == kindFilter).toList(growable: false);
        final ads = c.filterAndSort(filtered);
        if (ads.isEmpty) {
          return _EmptyState(
            kind: kindFilter,
            isSearching: c.searchQuery.isNotEmpty,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
          itemCount: ads.length,
          itemBuilder: (_, i) {
            final ad = ads[i];
            final canEdit = c.isOwner(ad) || c.isAdmin;
            return AdCard(
              ad: ad,
              canEdit: canEdit,
              onEdit: () =>
                  state == null ? null : state._onAdTapEdit(ad),
              onComplain: () =>
                  state == null ? null : state._onComplaintTap(ad),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind, required this.isSearching});

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
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Text(
                isSearching
                    ? 'Қидирув матнини ўзгартиринг'
                    : 'Биринчи бўлиб «$label» қўшинг!',
                style: TextStyle(
                    fontSize: AppText.bodySmall,
                    color: Colors.grey.shade400),
                textAlign: TextAlign.center,
              ),
            ]),
      ),
    );
  }
}
