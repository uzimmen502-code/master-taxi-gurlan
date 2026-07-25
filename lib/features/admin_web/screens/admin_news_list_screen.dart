import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
import '../services/admin_news_read_service.dart';
import '../../analytics/screens/admin_news_compose_screen.dart';

/// Админ web панели — News list screen.
///
/// Барча `admin_news` хужжатлaрни жонли (stream) кўрсaтaди. Ҳaр бирини
/// edit/delete қилиш мумкин. Янги хабaр учун compose экранига ўтaди.
class AdminNewsListScreen extends StatefulWidget {
  const AdminNewsListScreen({super.key});

  @override
  State<AdminNewsListScreen> createState() => _AdminNewsListScreenState();
}

class _AdminNewsListScreenState extends State<AdminNewsListScreen>
    with SingleTickerProviderStateMixin {
  String _filter = 'all'; // 'all' | 'user' | 'driver' | 'courier'
  final Set<String> _resendingPushIds = {};
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminNewsReadService>().markGeneralSeen();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isWalletTab => _tabController.index == 1;

  Future<void> _openCompose() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminNewsComposeScreen()),
    );
  }

  Future<void> _delete(NewsItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Хабaрни ўчириш?'),
        content: Text(
            '"${item.title}" хабaри тоzаланaди ва барчa фойдалaнувчилaрдaн '
            'йўq бўлaди. Бу амaлни бекор қилиш мумкин эмaс.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<NewsRepository>().delete(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('🗑 "${item.title}" ўчирилди'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатoлик: $e'),
        ),
      );
    }
  }

  Future<void> _resendPush(NewsItem item) async {
    if (!item.expectsPushFromAdmin || _resendingPushIds.contains(item.id)) {
      return;
    }

    const audienceResendLabels = <String, String>{
      'all': 'barcha foydalanuvchilarga',
      'user': 'foydalanuvchilarga',
      'driver': 'haydovchilarga',
      'courier': 'kuryerlarga',
    };

    final audienceLabel =
        audienceResendLabels[item.audience] ?? item.audience;
    final targetHint = item.isPersonal
        ? 'битта фойдалanuvchiga (${item.targetUserId})'
        : audienceLabel;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Push qayta yuborish?'),
        content: Text(
          '"${item.title}" хabari uchun push $targetHint '
          'qayta yuboriladi.\n\n'
          'Bu amalni istalgan vaqtda qayta bajarish mumkin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.notifications_active, size: 18),
            label: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _resendingPushIds.add(item.id));
    try {
      await context.read<NewsRepository>().requestPushResend(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('📲 "${item.title}" uchun push yuborildi'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Push xatolik: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resendingPushIds.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newsRepo = context.read<NewsRepository>();
    return Column(children: [
      _header(),
      _sectionTabs(),
      if (!_isWalletTab) _filterBar(),
      const Divider(height: 1),
      Expanded(
        child: StreamBuilder<List<NewsItem>>(
          stream: newsRepo.watchForAdmin(orderOnly: false, limit: 300),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _emptyState(
                icon: Icons.error_outline,
                color: Colors.red,
                title: 'Хатoлик',
                message: 'Хабaрлaрни юклaб бўлмaди: ${snap.error}',
              );
            }
            final allItems = snap.data ?? const <NewsItem>[];
            final scoped = _isWalletTab
                ? allItems.where((n) => n.isWalletNews).toList()
                : allItems.where((n) => !n.isWalletNews).toList();
            final filtered = (_isWalletTab || _filter == 'all')
                ? scoped
                : scoped.where((n) => n.audience == _filter).toList();
            if (filtered.isEmpty) {
              return _emptyState(
                icon: _isWalletTab
                    ? Icons.account_balance_wallet_outlined
                    : Icons.campaign_outlined,
                color: _isWalletTab ? const Color(0xFF00897B) : Colors.blue,
                title: _isWalletTab
                    ? 'Ҳали wallet хабар ёқ'
                    : 'Ҳали хабар ёқ',
                message: _isWalletTab
                    ? 'Telegram ҳамён тўлдириш/ечиш хабарлари шу ерда чиқади.'
                    : 'Янги хабaр ёзиш учун юқoри ўнгдaги "+ Янги хабaр" '
                        'тугмaсини бoсинг.',
              );
            }
            if (_isWalletTab) {
              return _WalletNewsList(items: filtered);
            }
            return _ResponsiveGrid(
              items: filtered,
              onDelete: _delete,
              onResendPush: _resendPush,
              resendingPushIds: _resendingPushIds,
            );
          },
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        const Text('📣 Хабaрлaр',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (!_isWalletTab)
          ElevatedButton.icon(
            onPressed: _openCompose,
            icon: const Icon(Icons.add),
            label: const Text('Янги хабaр'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
      ]),
    );
  }

  Widget _sectionTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        tabs: const [
          Tab(
            icon: Icon(Icons.campaign_outlined, size: 18),
            text: 'Умумий',
            height: 48,
          ),
          Tab(
            icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
            text: 'Wallet',
            height: 48,
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final filters = [
      ('all', 'Барчaси', Icons.public),
      ('user', 'Фойдалaнувчи', Icons.person),
      ('driver', 'Ҳaйдовчи', Icons.directions_car),
      ('courier', 'Курьер', Icons.delivery_dining),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Colors.white,
      child: Wrap(spacing: 8, children: [
        for (final f in filters)
          ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(f.$3, size: 14),
              const SizedBox(width: 4),
              Text(f.$2),
            ]),
            selected: _filter == f.$1,
            onSelected: (_) => setState(() => _filter = f.$1),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: _filter == f.$1
                  ? AppColors.primary
                  : Colors.grey.shade700,
              fontWeight:
                  _filter == f.$1 ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
      ]),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: color),
          ),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

/// Фойдаланувчи бўйича Telegram тўлдириш суммалари.
class _UserTopUpSums {
  const _UserTopUpSums({this.pending = 0, this.paid = 0});
  final int pending;
  final int paid;
  int get total => pending + paid;
}

/// Wallet хабарлари — фойдаланувчи катаги; тўлдиришлар №1, №2… (охиргиси юқорида).
class _WalletNewsList extends StatefulWidget {
  const _WalletNewsList({required this.items});
  final List<NewsItem> items;

  @override
  State<_WalletNewsList> createState() => _WalletNewsListState();
}

class _WalletNewsListState extends State<_WalletNewsList> {
  static final _amountRe =
      RegExp(r'([+-]?\d[\d\s]*)\s*сўм', caseSensitive: false);
  static final _dtFmt = DateFormat('dd.MM.yyyy HH:mm');
  static const _pendingStatuses = {
    // Фақат чек юкланган, админ тасдиғи кутилаётган.
    // awaiting_transfer — пул ҳали ўтмаган / бекор қолиши мумкин → жамига қўшилмайди.
    'awaiting_review',
  };

  /// canonicalPhoneId → display name
  final Map<String, String> _names = {};

  /// canonicalPhoneId → ҳамён баланси (bonusBalance)
  final Map<String, int> _balances = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _topUpSub;
  Map<String, _UserTopUpSums> _topUpByUid = {};

  @override
  void initState() {
    super.initState();
    _loadNames();
    _listenTopUps();
  }

  @override
  void dispose() {
    _topUpSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WalletNewsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _loadNames();
    }
  }

  void _listenTopUps() {
    _topUpSub?.cancel();
    _topUpSub = FirebaseFirestore.instance
        .collection('wallet_topup_requests')
        .snapshots()
        .listen((snap) {
      final map = <String, _UserTopUpSums>{};
      for (final doc in snap.docs) {
        final m = doc.data();
        final uid = canonicalPhoneId('${m['uid'] ?? ''}');
        if (uid.isEmpty) continue;
        final amount = (m['amount'] as num?)?.toInt() ?? 0;
        if (amount <= 0) continue;
        final status = '${m['status'] ?? ''}';
        final prev = map[uid] ?? const _UserTopUpSums();
        if (_pendingStatuses.contains(status)) {
          map[uid] = _UserTopUpSums(
            pending: prev.pending + amount,
            paid: prev.paid,
          );
        } else if (status == 'credited') {
          map[uid] = _UserTopUpSums(
            pending: prev.pending,
            paid: prev.paid + amount,
          );
        }
      }
      if (!mounted) return;
      setState(() => _topUpByUid = map);
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _topUpByUid = {});
    });
  }

  Future<void> _loadNames() async {
    final ids = <String>{};
    for (final item in widget.items) {
      final id = canonicalPhoneId(item.targetUserId);
      if (id.isNotEmpty && !_names.containsKey(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      final list = ids.toList();
      for (var i = 0; i < list.length; i += 10) {
        final chunk = list.sublist(i, (i + 10).clamp(0, list.length));
        final snaps = await Future.wait(
          chunk.map((id) => db.collection('users').doc(id).get()),
        );
        for (final snap in snaps) {
          if (!snap.exists) {
            _names[snap.id] = '';
            _balances[snap.id] = 0;
            continue;
          }
          final data = snap.data() ?? const <String, dynamic>{};
          _names[snap.id] = '${data['name'] ?? ''}'.trim();
          _balances[snap.id] =
              (data['bonusBalance'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {
      // Исм топилмаса телефон қолadi.
    }
    if (mounted) setState(() {});
  }

  String amountOf(NewsItem item) {
    final m = _amountRe.firstMatch(item.body);
    if (m != null) {
      final raw = m.group(1)!.replaceAll(RegExp(r'\s'), '');
      return '$raw сўм';
    }
    final body = item.body.trim();
    return body.isEmpty ? '—' : body;
  }

  String phoneOf(NewsItem item) {
    final u = item.targetUserId.trim();
    return u.isEmpty ? '—' : u;
  }

  String nameOf(NewsItem item) {
    final id = canonicalPhoneId(item.targetUserId);
    if (id.isEmpty) return '';
    return (_names[id] ?? '').trim();
  }

  bool isCredit(NewsItem item) {
    final t = '${item.title} ${item.body} ${item.source}'.toLowerCase();
    if (t.contains('withdraw') || t.contains('ечил') || t.contains('yech')) {
      return false;
    }
    if (item.body.trim().startsWith('-')) return false;
    return true;
  }

  Widget _kvRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Фойдаланувчи бўйича гуруҳ: охирги фаоллик аввал.
  List<({String uid, List<NewsItem> items, Map<String, int> seq})> _groups() {
    final byUid = <String, List<NewsItem>>{};
    for (final item in widget.items) {
      final uid = canonicalPhoneId(item.targetUserId);
      final key = uid.isEmpty ? '_${item.id}' : uid;
      (byUid[key] ??= []).add(item);
    }

    final groups = <({String uid, List<NewsItem> items, Map<String, int> seq})>[];
    for (final e in byUid.entries) {
      final chronological = [...e.value]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final seq = <String, int>{};
      for (var i = 0; i < chronological.length; i++) {
        seq[chronological[i].id] = i + 1;
      }
      final newestFirst = [...chronological.reversed];
      groups.add((
        uid: e.key.startsWith('_') ? '' : e.key,
        items: newestFirst,
        seq: seq,
      ));
    }
    groups.sort((a, b) {
      final aAt = a.items.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : a.items.first.createdAt;
      final bAt = b.items.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : b.items.first.createdAt;
      return bAt.compareTo(aAt);
    });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: groups.length,
      separatorBuilder: (_, __) => Divider(height: 20, color: Colors.grey.shade300),
      itemBuilder: (ctx, gi) {
        final group = groups[gi];
        final head = group.items.first;
        final uid = group.uid.isNotEmpty
            ? group.uid
            : canonicalPhoneId(head.targetUserId);
        final name = nameOf(head);
        final phone = phoneOf(head);
        final sums = _topUpByUid[uid] ?? const _UserTopUpSums();
        final walletBal = _balances[uid];

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (name.isNotEmpty) phone,
                  if (walletBal != null)
                    'баланс ${formatPrice(walletBal)} сўм',
                ].where((s) => s.trim().isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              _kvRow(
                'Тўлов қилингунча',
                '${formatPrice(sums.pending)} сўм',
                valueColor: const Color(0xFFE65100),
              ),
              _kvRow(
                'Тўлов қилинган',
                '${formatPrice(sums.paid)} сўм',
                valueColor: const Color(0xFF00897B),
              ),
              _kvRow(
                'Жами',
                '${formatPrice(sums.total)} сўм',
                valueColor: const Color(0xFF1565C0),
              ),
              const SizedBox(height: 6),
              for (final item in group.items)
                _eventRow(
                  item: item,
                  number: group.seq[item.id] ?? 0,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _eventRow({required NewsItem item, required int number}) {
    final credit = isCredit(item);
    final accent =
        credit ? const Color(0xFF00897B) : const Color(0xFFD32F2F);
    final title = item.title.trim().isEmpty ? 'Wallet' : item.title.trim();
    final when = _dtFmt.format(item.createdAt);
    final line = '$number. $title · ${amountOf(item)} · $when';

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        line,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.items,
    required this.onDelete,
    required this.onResendPush,
    required this.resendingPushIds,
  });
  final List<NewsItem> items;
  final ValueChanged<NewsItem> onDelete;
  final ValueChanged<NewsItem> onResendPush;
  final Set<String> resendingPushIds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      final pad = width > 800 ? 24.0 : 12.0;
      final cols = (width / 380).floor().clamp(1, 4);
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          mainAxisExtent: 288,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _NewsCard(
          item: items[i],
          onDelete: () => onDelete(items[i]),
          onResendPush: () => onResendPush(items[i]),
          resendingPush: resendingPushIds.contains(items[i].id),
        ),
      );
    });
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.item,
    required this.onDelete,
    required this.onResendPush,
    required this.resendingPush,
  });
  final NewsItem item;
  final VoidCallback onDelete;
  final VoidCallback onResendPush;
  final bool resendingPush;

  static const _categoryColors = <String, Color>{
    'info': AppColors.primary,
    'update': AppColors.primary,
    'promo': AppColors.primary,
    'warning': Color(0xFFFFA000),
    'emergency': Color(0xFFD32F2F),
    'wallet': Color(0xFF00897B),
  };

  static const _categoryIcons = <String, IconData>{
    'info': Icons.info_outline,
    'update': Icons.system_update_alt,
    'promo': Icons.local_offer,
    'warning': Icons.warning_amber,
    'emergency': Icons.crisis_alert,
    'wallet': Icons.account_balance_wallet_outlined,
  };

  static const _categoryLabels = <String, String>{
    'info': 'Маълумoт',
    'update': 'Янгилaниш',
    'promo': 'Аксия',
    'warning': 'Огoҳлaнтириш',
    'emergency': 'Шошилинч',
    'wallet': 'Wallet',
  };

  static const _audienceLabels = <String, String>{
    'all': '🌐 Барчaси',
    'user': '👤 Фойдалaнувчи',
    'driver': '🚖 Ҳaйдовчи',
    'courier': '🛵 Курьер',
  };

  @override
  Widget build(BuildContext context) {
    final color = _categoryColors[item.category] ?? Colors.grey;
    final icon = _categoryIcons[item.category] ?? Icons.notes;
    final catLabel = _categoryLabels[item.category] ?? item.category;
    final audLabel = _audienceLabels[item.audience] ?? item.audience;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(catLabel,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(audLabel,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade700)),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(item.body,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (item.ctaLabel.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.link, size: 12, color: color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(item.ctaLabel,
                              style: TextStyle(fontSize: 11, color: color),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  if (item.hasPushStats || item.pushPending)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _PushStatusChip(item: item),
                    ),
                ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
          child: Row(children: [
            Icon(Icons.schedule, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(DateFormat('dd.MM.yyyy HH:mm').format(item.createdAt),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
            const Spacer(),
            if (item.expectsPushFromAdmin)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: resendingPush
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue.shade700,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: onResendPush,
                        icon: const Icon(Icons.notifications_active, size: 14),
                        label: const Text('Push qayta'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            if (item.priority > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('⭐ ${item.priority}',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold)),
              ),
            // TODO: delete — Phone Auth + isSuperAdmin() tayyor bo'lgach ochiladi
            // InkWell(
            //   onTap: onDelete,
            //   borderRadius: BorderRadius.circular(4),
            //   child: Padding(
            //     padding: const EdgeInsets.all(4),
            //     child: Icon(Icons.delete_outline,
            //         size: 16, color: Colors.red.shade400),
            //   ),
            // ),
          ]),
        ),
      ]),
    );
  }
}

/// Push статистикаси — CF `pushSentCount` / `pushBroadcastAt` майдонлари.
class _PushStatusChip extends StatelessWidget {
  const _PushStatusChip({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    if (item.hasPushStats) {
      final count = item.pushSentCount ?? 0;
      final at = item.pushBroadcastAt;
      final timeStr =
          at != null ? DateFormat('HH:mm').format(at) : '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: count > 0 ? AppColors.scaffold : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: count > 0 ? AppColors.primary.withValues(alpha: 0.25) : Colors.orange.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active,
              size: 14,
              color: count > 0 ? AppColors.primaryDark : Colors.orange.shade800,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                count > 0
                    ? 'Push: $count ta yuborildi'
                    : 'Push: 0 ta (token yoвЂq)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: count > 0
                      ? AppColors.primaryDark
                      : Colors.orange.shade900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      );
    }

    if (item.pushPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Push yuborilmoqda…',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade800,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
