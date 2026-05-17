import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
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

class _AdminNewsListScreenState extends State<AdminNewsListScreen> {
  String _filter = 'all'; // 'all' | 'user' | 'driver' | 'courier'

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
          backgroundColor: Colors.green,
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

  @override
  Widget build(BuildContext context) {
    final newsRepo = context.read<NewsRepository>();
    return Column(children: [
      _header(),
      _filterBar(),
      const Divider(height: 1),
      Expanded(
        child: StreamBuilder<List<NewsItem>>(
          stream: newsRepo.watchAll(audiences: const ['all'], limit: 200),
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
            final filtered = _filter == 'all'
                ? allItems
                : allItems.where((n) => n.audience == _filter).toList();
            if (filtered.isEmpty) {
              return _emptyState(
                icon: Icons.campaign_outlined,
                color: Colors.blue,
                title: 'Ҳaли хабaр йоq',
                message: 'Янги хабaр ёзиш учун юқoри ўнгдaги "+ Янги хабaр" '
                    'тугмaсини бoсинг.',
              );
            }
            return _ResponsiveGrid(items: filtered, onDelete: _delete);
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        const Text('📣 Хабaрлaр',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _openCompose,
          icon: const Icon(Icons.add),
          label: const Text('Янги хабaр'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
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
            selectedColor: const Color(0xFF0D47A1).withOpacity(0.15),
            labelStyle: TextStyle(
              color: _filter == f.$1
                  ? const Color(0xFF0D47A1)
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
              color: color.withOpacity(0.1),
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

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.items, required this.onDelete});
  final List<NewsItem> items;
  final ValueChanged<NewsItem> onDelete;

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
          mainAxisExtent: 220,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            _NewsCard(item: items[i], onDelete: () => onDelete(items[i])),
      );
    });
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onDelete});
  final NewsItem item;
  final VoidCallback onDelete;

  static const _categoryColors = <String, Color>{
    'info': Color(0xFF1565C0),
    'update': Color(0xFF6A1B9A),
    'promo': Color(0xFFE65100),
    'warning': Color(0xFFFFA000),
    'emergency': Color(0xFFD32F2F),
  };

  static const _categoryIcons = <String, IconData>{
    'info': Icons.info_outline,
    'update': Icons.system_update_alt,
    'promo': Icons.local_offer,
    'warning': Icons.warning_amber,
    'emergency': Icons.crisis_alert,
  };

  static const _categoryLabels = <String, String>{
    'info': 'Маълумoт',
    'update': 'Янгилaниш',
    'promo': 'Аксия',
    'warning': 'Огoҳлaнтириш',
    'emergency': 'Шошилинч',
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
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
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
                        color: color.withOpacity(0.1),
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
