import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
import '../services/admin_news_read_service.dart';

/// Admin вЂ” mijozga yuborilgan buyurtma status xabarlari (`admin_news`).
class AdminOrderNewsListScreen extends StatefulWidget {
  const AdminOrderNewsListScreen({super.key});

  @override
  State<AdminOrderNewsListScreen> createState() =>
      _AdminOrderNewsListScreenState();
}

class _AdminOrderNewsListScreenState extends State<AdminOrderNewsListScreen> {
  static const _orange = AppColors.primary;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminNewsReadService>().markOrderSeen();
    });
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'new':
        return 'Р®Р±РѕСЂРёР»РґРё';
      case 'accepted':
        return 'ТљР°Р±СѓР»';
      case 'ready':
        return 'РўР°Р№С‘СЂ';
      case 'in_delivery':
        return 'Р™СћР»РґР°';
      case 'delivered':
        return 'Р•С‚РєР°Р·РёР»РґРё';
      case 'rejected':
        return 'Р Р°Рґ';
      default:
        return s.isEmpty ? 'вЂ”' : s;
    }
  }

  List<NewsItem> _filter(List<NewsItem> items) {
    if (_statusFilter == 'all') return items;
    return items
        .where((n) => n.orderStatus == _statusFilter)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final newsRepo = context.read<NewsRepository>();
    return Column(
      children: [
        _header(),
        _filterBar(),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<NewsItem>>(
            stream: newsRepo.watchForAdmin(orderOnly: true, limit: 300),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text('РҐР°С‚РѕР»РёРє: ${snap.error}',
                      style: const TextStyle(color: Colors.red)),
                );
              }
              final items = _filter(snap.data ?? const []);
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Р‘СѓСЋСЂС‚РјР° С…abarlar Р№СћТ›',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
                      const SizedBox(height: 6),
                      Text(
                        'Buyurtma yuborilganda yoki status oвЂzgarganda shu yerda koвЂrinadi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }
              return _ResponsiveGrid(items: items, statusLabel: _statusLabel);
            },
          ),
        ),
      ],
    );
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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sms_outlined, color: _orange),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'рџ“‹ Р‘СѓСЋСЂС‚РјР° С…Р°Р±Р°СЂ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Mijozga yuborilgan avtomatik status xabarlari',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    const filters = [
      ('all', 'Р‘Р°СЂС‡asi'),
      ('new', 'Р®Р±РѕСЂРёР»РґРё'),
      ('accepted', 'ТљР°Р±СѓР»'),
      ('ready', 'РўР°Р№С‘СЂ'),
      ('in_delivery', 'Р™СћР»РґР°'),
      ('delivered', 'Р•С‚РєР°Р·РёР»РґРё'),
      ('rejected', 'Р Р°Рґ'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Colors.white,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in filters)
            ChoiceChip(
              label: Text(f.$2),
              selected: _statusFilter == f.$1,
              onSelected: (_) => setState(() => _statusFilter = f.$1),
              selectedColor: _orange.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                color: _statusFilter == f.$1 ? _orange : Colors.grey.shade700,
                fontWeight:
                    _statusFilter == f.$1 ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.items,
    required this.statusLabel,
  });

  final List<NewsItem> items;
  final String Function(String) statusLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final width = constraints.maxWidth;
        final pad = width > 800 ? 24.0 : 12.0;
        final cols = (width / 380).floor().clamp(1, 4);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 260,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _OrderNewsCard(
            item: items[i],
            statusLabel: statusLabel,
          ),
        );
      },
    );
  }
}

class _OrderNewsCard extends StatelessWidget {
  const _OrderNewsCard({
    required this.item,
    required this.statusLabel,
  });

  final NewsItem item;
  final String Function(String) statusLabel;

  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final typeLabel =
        item.orderType == 'food' ? 'рџЌЅ РўР°Р№С‘СЂ РѕРІТ›Р°С‚' : 'рџЌћ РќРѕРЅ Р±СѓСЋСЂС‚РјР°';
    final status = statusLabel(item.orderStatus);
  final phone = item.targetUserId.isNotEmpty ? item.targetUserId : 'вЂ”';
    final orderId = item.orderId.isNotEmpty
        ? (item.orderId.length > 10
            ? '${item.orderId.substring(0, 10)}вЂ¦'
            : item.orderId)
        : 'вЂ”';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: _orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: _orange,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  typeLabel,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      item.body,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('рџ“± $phone',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                  Text('рџ†” $orderId',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd.MM.yyyy HH:mm').format(item.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (item.priority > 0)
                  Text(
                    'в­ђ ${item.priority}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
