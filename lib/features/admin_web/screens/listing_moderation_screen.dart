import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_listing_moderation_service.dart';
import '../utils/listing_moderation.dart';
import '../widgets/admin_reason_dialog.dart';

typedef ListingModLoader = Future<List<ListingModItem>> Function(ListingModSource source);
typedef ListingModAction = Future<void> Function(
  ListingModSource source,
  String id, {
  required bool approve,
  String? reason,
});

/// «Эълонлар модерацияси» (Бозорлар 2b, эга 2026-11-15): барча бозорлардаги `pending` эълонлар бир жойда.
/// Тасдиқлаш / рад этиш — сервер `adminModerateListing` (audit + сотувчига хабар). Мавжуд модерация
/// экранлари ўзгармаган — бу экран уларнинг ёнида.
class ListingModerationScreen extends StatelessWidget {
  const ListingModerationScreen({super.key, this.loadPending, this.moderate});

  /// Тест учун алмаштирилади; бўлмаса — [AdminListingModerationService].
  final ListingModLoader? loadPending;
  final ListingModAction? moderate;

  @override
  Widget build(BuildContext context) {
    final service = AdminListingModerationService();
    final load = loadPending ?? service.fetchPending;
    final act = moderate ??
        (ListingModSource s, String id, {required bool approve, String? reason}) =>
            service.moderate(source: s, id: id, approve: approve, reason: reason);
    return DefaultTabController(
      length: ListingModSource.values.length,
      child: Column(
        children: [
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
              children: [for (final s in ListingModSource.values) _SourceList(source: s, load: load, act: act)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceList extends StatefulWidget {
  const _SourceList({required this.source, required this.load, required this.act});

  final ListingModSource source;
  final ListingModLoader load;
  final ListingModAction act;

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
    // Оптимистик: рўйхатдан дарҳол олинади; хато бўлса жойига қайтади.
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index < 0) return;
    setState(() => _items = [..._items]..removeAt(index));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.act(widget.source, item.id, approve: approve, reason: reason);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(approve ? 'Тасдиқланди: ${item.title}' : 'Рад этилди: ${item.title}')));
    } catch (e) {
      debugPrint('[ListingModeration] ${approve ? 'approve' : 'reject'} ${widget.source.collection}/${item.id}: $e');
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
    final markets = widget.source == ListingModSource.shop
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
                'Текширувда: ${visible.length}${_items.length >= kListingModPageLimit ? ' (биринчи $kListingModPageLimit та)' : ''}',
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('Текширувни кутаётган эълон йўқ')),
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
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  key: ValueKey('lmod_approve_${it.id}'),
                  onPressed: () => _decide(it, approve: true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Тасдиқлаш'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
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
