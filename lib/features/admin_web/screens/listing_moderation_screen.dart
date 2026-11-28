import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_listing_moderation_service.dart';
import '../services/admin_moderation_modes_service.dart';
import '../utils/listing_moderation.dart';
import '../widgets/admin_reason_dialog.dart';
import '../widgets/listing_edit_dialog.dart';
import '../widgets/moderation_mode_bar.dart';

typedef ListingModLoader = Future<List<ListingModItem>> Function(ListingModSource source);
typedef ListingModAction = Future<void> Function(
  ListingModSource source,
  String id, {
  required bool approve,
  String? reason,
});

/// «Тузатиш ва тасдиқлаш»: `edits` (фақат ўзгарган майдонлар; бўш — оддий тасдиқ) + approve.
typedef ListingModEditApprove = Future<void> Function(ListingModSource source, String id, Map<String, Object?> edits);
typedef ListingModCategoriesLoader = Future<Map<String, List<ListingModCategory>>> Function();

/// `settings/app.shopItemAutoApprove` samarali qiymati oqimi (maydon yo'q = Қўлда). Test uchun almashtiriladi;
/// bo'lmasa — [ModerationModeBar] o'zi `adminGetModerationModes` + `settings/app` oqimidan oladi.
typedef ShopAutoApproveWatch = ModerationModeWatch;

/// Bo'lmasa — `adminSetModerationMode` (mode `shopItem`, server audit, ega 2026-11-28 audit C-1).
typedef ShopAutoApproveSet = ModerationModeSet;

/// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15): барча бозорлардаги `pending` эълонлар бир жойда.
/// Тасдиқлаш / рад этиш — сервер `adminModerateListing` (audit + сотувчига хабар). Мавжуд модерация
/// экранлари ўзгармаган — бу экран уларнинг ёнида.
/// «Админ тузатиб тасдиқлайди» (эга 2026-11-15): tv_shop_items карточкасида «Тузатиш ва тасдиқлаш»;
/// «Рад этилганлар» таби — рад этилган tv_shop_items (сотувчи қайта юбормайди, админ тузатади).
class ListingModerationScreen extends StatelessWidget {
  const ListingModerationScreen({
    super.key,
    this.loadPending,
    this.moderate,
    this.editApprove,
    this.loadCategories,
    this.watchShopAutoApprove,
    this.setShopAutoApprove,
  });

  /// Тест учун алмаштирилади; бўлмаса — [AdminListingModerationService].
  final ListingModLoader? loadPending;
  final ListingModAction? moderate;
  final ListingModEditApprove? editApprove;
  final ListingModCategoriesLoader? loadCategories;

  /// «Авто тасдиқ / Қўлда» (эга 2026-11-19) — тест учун; бўлмаса Firestore `settings/app`.
  final ShopAutoApproveWatch? watchShopAutoApprove;
  final ShopAutoApproveSet? setShopAutoApprove;

  @override
  Widget build(BuildContext context) {
    final service = AdminListingModerationService();
    final load = loadPending ?? service.fetchPending;
    final act = moderate ??
        (ListingModSource s, String id, {required bool approve, String? reason}) =>
            service.moderate(source: s, id: id, approve: approve, reason: reason);
    final edit = editApprove ??
        (ListingModSource s, String id, Map<String, Object?> edits) =>
            service.moderate(source: s, id: id, approve: true, edits: edits);
    final cats = loadCategories ?? service.fetchMarketCategories;
    return DefaultTabController(
      length: ListingModSource.values.length,
      child: Column(
        children: [
          // «Авто тасдиқ / Қўлда» (эга 2026-11-19): фақат бозорлардаги маҳсулотлар (`tv_shop_items`).
          ModerationModeBar(
            mode: ModerationMode.shopItem,
            keyPrefix: 'lmod',
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            onLabel: 'Авто тасдиқ: ЁҚИҚ — маҳсулотлар дарҳол актив',
            offLabel: 'Қўлда тасдиқ — маҳсулотлар «Текширувда»га тушади',
            hint: 'Фақат бозорлардаги янги ва таҳрирланган маҳсулотларга таъсир қилади.',
            confirmTitle: 'Авто тасдиқни ёқасизми?',
            confirmBody: 'Бозорлардаги янги ва таҳрирланган маҳсулотлар текширувсиз дарҳол кўринади. '
                'Рад этиш кейин ҳам мумкин.',
            watch: watchShopAutoApprove,
            set: setShopAutoApprove,
          ),
          Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelColor: AvaLight.brand,
              indicatorColor: AvaLight.brand,
              tabs: [for (final s in ListingModSource.values) Tab(key: ValueKey('lmod_tab_${s.name}'), text: s.label)],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final s in ListingModSource.values)
                  _SourceList(source: s, load: load, act: act, editApprove: edit, loadCategories: cats),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceList extends StatefulWidget {
  const _SourceList({
    required this.source,
    required this.load,
    required this.act,
    required this.editApprove,
    required this.loadCategories,
  });

  final ListingModSource source;
  final ListingModLoader load;
  final ListingModAction act;
  final ListingModEditApprove editApprove;
  final ListingModCategoriesLoader loadCategories;

  @override
  State<_SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<_SourceList> with AutomaticKeepAliveClientMixin {
  List<ListingModItem> _items = const [];
  bool _loading = true;
  String? _error;

  /// Бозор фильтри (фақат «Аралаш / дўкон», ҳужжатда `market` бўлса); `null` — барчаси.
  String? _market;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.load(widget.source);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        if (_market != null && !items.any((i) => i.market == _market)) _market = null;
      });
    } catch (e) {
      debugPrint('[ListingModeration] load ${widget.source.collection}: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Тўлиқ хато (индекс ҳаволаси билан) — логда; экранда — код.
        _error = 'Рўйхатни юклаб бўлмади (${e is FirebaseException ? e.code : 'CLIENT_ERROR'}).';
      });
    }
  }

  Future<void> _decide(ListingModItem item, {required bool approve}) async {
    String? reason;
    if (!approve) {
      reason = await showAdminReasonDialog(
        context,
        title: 'Рад этиш',
        message: '«${item.title}» — сабаб сотувчига юборилади (1–$kListingRejectReasonMax белги).',
        minLength: 1,
        confirmLabel: 'Рад этиш',
      );
      if (reason == null || !mounted) return;
      if (!listingRejectReasonValid(reason)) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Рад этиш сабабини ёзинг (1–300 белги)')));
        return;
      }
    }
    await _optimistic(
      item,
      label: approve ? 'approve' : 'reject',
      run: () => widget.act(widget.source, item.id, approve: approve, reason: reason),
      success: approve ? 'Тасдиқланди: ${item.title}' : 'Рад этилди: ${item.title}',
    );
  }

  Map<String, List<ListingModCategory>>? _categories;

  /// Бўлимлар бир марта юкланади; хато — бўш (диалогда матн майдони қолади).
  Future<List<ListingModCategory>> _categoriesFor(String market) async {
    if (market.isEmpty) return const [];
    if (_categories == null) {
      try {
        _categories = await widget.loadCategories();
      } catch (e) {
        debugPrint('[ListingModeration] taxonomy: $e');
        _categories = const {};
      }
    }
    return _categories![market] ?? const [];
  }

  Future<void> _editApprove(ListingModItem item) async {
    final categories = await _categoriesFor(item.market);
    if (!mounted) return;
    final edits = await showListingEditDialog(context, item, categories: categories);
    if (edits == null || !mounted) return;
    await _optimistic(
      item,
      label: 'edit_approve',
      run: () => widget.editApprove(widget.source, item.id, edits),
      success: edits.isEmpty ? 'Тасдиқланди: ${item.title}' : 'Тузатилди ва тасдиқланди: ${edits['title'] ?? item.title}',
    );
  }

  /// Оптимистик: рўйхатдан дарҳол олинади; хато бўлса жойига қайтади ва код кўрсатилади.
  Future<void> _optimistic(
    ListingModItem item, {
    required String label,
    required Future<void> Function() run,
    required String success,
  }) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    setState(() => _items = [..._items]..removeAt(index));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await run();
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      debugPrint('[ListingModeration] $label ${widget.source.collection}/${item.id}: $e');
      if (!mounted) return;
      setState(() {
        final list = [..._items];
        list.insert(index.clamp(0, list.length), item);
        _items = list;
      });
      // Аввалги («Тасдиқланди») хабар навбатда турмасин — хато дарҳол кўринсин.
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(listingModErrorText(e)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
          OutlinedButton(onPressed: _refresh, child: const Text('Қайта юклаш')),
        ]),
      );
    }
    final markets = widget.source.editable
        ? (_items.map((i) => i.market).where((m) => m.isNotEmpty).toSet().toList()..sort())
        : const <String>[];
    final visible = _market == null ? _items : _items.where((i) => i.market == _market).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${widget.source.canReject ? 'Текширувда' : 'Рад этилган'}: ${visible.length}${_items.length >= kListingModPageLimit ? ' (биринчи $kListingModPageLimit та)' : ''}',
                key: ValueKey('lmod_count_${widget.source.name}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(tooltip: 'Янгилаш', icon: const Icon(Icons.refresh), onPressed: _refresh),
          ]),
          if (markets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  key: const ValueKey('lmod_market_all'),
                  label: const Text('Барчаси'),
                  selected: _market == null,
                  onSelected: (_) => setState(() => _market = null),
                ),
                for (final m in markets)
                  ChoiceChip(
                    key: ValueKey('lmod_market_$m'),
                    label: Text(m),
                    selected: _market == m,
                    onSelected: (_) => setState(() => _market = m),
                  ),
              ]),
            ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(widget.source.canReject ? 'Текширувни кутаётган эълон йўқ' : 'Рад этилган эълон йўқ'),
              ),
            ),
          for (final it in visible) _card(it),
        ],
      ),
    );
  }

  Widget _card(ListingModItem it) {
    final meta = [
      if (it.seller.isNotEmpty) it.seller,
      if (it.market.isNotEmpty) it.market,
      if (it.category.isNotEmpty) it.category,
      'Юборилган: ${listingModTimeLabel(it.submittedAt)}',
    ].join(' · ');
    return Card(
      key: ValueKey('lmod_card_${it.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 88,
            height: 88,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: it.photoUrl.isEmpty
                  ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.image_not_supported_outlined))
                  : Image.network(it.photoUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title.isEmpty ? '—' : it.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (it.priceText.isNotEmpty) Text(it.priceText),
              const SizedBox(height: 2),
              Text(meta, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              if (it.rejectReason.isNotEmpty && !widget.source.canReject)
                Text('Рад этиш сабаби: ${it.rejectReason}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  key: ValueKey('lmod_approve_${it.id}'),
                  onPressed: () => _decide(it, approve: true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Тасдиқлаш'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
                if (widget.source.editable)
                  OutlinedButton.icon(
                    key: ValueKey('lmod_edit_${it.id}'),
                    onPressed: () => _editApprove(it),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Тузатиш ва тасдиқлаш'),
                  ),
                if (widget.source.canReject)
                  OutlinedButton.icon(
                    key: ValueKey('lmod_reject_${it.id}'),
                    onPressed: () => _decide(it, approve: false),
                    icon: Icon(Icons.block, size: 18, color: Colors.red.shade700),
                    label: Text('Рад этиш', style: TextStyle(color: Colors.red.shade700)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
