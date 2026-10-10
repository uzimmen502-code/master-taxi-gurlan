import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
import '../services/admin_news_read_service.dart';

/// Филтр калити: статуссиз буюртма хабарлари (курьер етиб келди, тўлов /
/// йиғим чеки, ресторан хабарлари).
@visibleForTesting
const kOrderNewsOtherFilter = 'other';

/// Карточкадаги ҳолат ёрлиғи: статус хабарида — статус, бошқаларида —
/// манба (аввал `—` ёки хом `cancelled` чиқарди).
@visibleForTesting
String orderNewsStatusLabel(NewsItem n) {
  switch (n.orderStatus) {
    case 'new':
      return 'Юборилди';
    case 'accepted':
      return 'Қабул';
    case 'ready':
      return 'Тайёр';
    case 'in_delivery':
      return 'Йўлда';
    case 'delivered':
      return 'Етказилди';
    case 'rejected':
      return 'Рад';
    case 'cancelled':
      return 'Бекор';
  }
  if (n.orderStatus.isNotEmpty) return n.orderStatus;
  switch (n.source) {
    case 'courier_arrived':
      return 'Курьер етиб келди';
    case 'payment_receipt':
      return 'Тўлов чеки';
    case 'collection_receipt':
      return 'Йиғим чеки';
    case 'restaurant_order':
      return 'Ресторан';
    default:
      return '—';
  }
}

/// Карточкадаги буюртма тури. Эски `food` хабарлари рўйхатга тушмайди
/// ([NewsItem.isRemovedFoodOrderNews]).
@visibleForTesting
String orderNewsTypeLabel(NewsItem n) {
  switch (n.orderType) {
    case 'bread':
      return '🍞 Нон буюртма';
    case 'platform':
      return '🛒 Улгуржи бозор';
    case 'restaurant':
      return '🍽 Кафе-ресторан';
    default:
      return n.source == 'restaurant_order' ? '🍽 Кафе-ресторан' : '📦 Буюртма';
  }
}

/// Филтр: `all`, статус ёки [kOrderNewsOtherFilter].
@visibleForTesting
List<NewsItem> filterOrderNews(List<NewsItem> items, String filter) {
  if (filter == 'all') return items;
  if (filter == kOrderNewsOtherFilter) {
    return items.where((n) => n.orderStatus.isEmpty).toList(growable: false);
  }
  return items.where((n) => n.orderStatus == filter).toList(growable: false);
}

/// Admin — буюртма бўйича юборилган автоматик хабарлар (`admin_news`,
/// `category == 'order'`).
class AdminOrderNewsListScreen extends StatefulWidget {
  const AdminOrderNewsListScreen({super.key});

  @override
  State<AdminOrderNewsListScreen> createState() =>
      _AdminOrderNewsListScreenState();
}

class _AdminOrderNewsListScreenState extends State<AdminOrderNewsListScreen> {
  static const _orange = AppColors.primary;
  String _statusFilter = 'all';
  late final Stream<List<NewsItem>> _stream;

  @override
  void initState() {
    super.initState();
    // Битта listener: аввал ҳар build'да янги сўров очиларди (филтр
    // чипи босилганда ҳам 300 ҳужжат қайта ўқиларди).
    _stream =
        context.read<NewsRepository>().watchForAdmin(orderOnly: true, limit: 300);
  }

  /// Экран очиқ турганда келган хабар ҳам «кўрилган» — белги энг янги
  /// хабарнинг сервер вақти (админ соатига боғлиқ эмас).
  void _markSeen(List<NewsItem> all) {
    if (all.isEmpty) return;
    final newest = all
        .map((n) => n.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminNewsReadService>().markOrderSeen(newest);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _filterBar(),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<NewsItem>>(
            stream: _stream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text('Хатолик: ${snap.error}',
                      style: const TextStyle(color: Colors.red)),
                );
              }
              final all = snap.data ?? const <NewsItem>[];
              _markSeen(all);
              final items = filterOrderNews(all, _statusFilter);
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Буюртма хабарлари йўқ',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
                      const SizedBox(height: 6),
                      Text(
                        'Буюртма юборилганда ёки ҳолати ўзгарганда шу ерда кўринади',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }
              return _ResponsiveGrid(items: items);
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
            child: const Icon(Icons.sms_outlined, color: AppColors.primaryText),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📋 Буюртма хабар',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Буюртма бўйича юборилган автоматик хабарлар',
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
      ('all', 'Барчаси'),
      ('new', 'Юборилди'),
      ('accepted', 'Қабул'),
      ('ready', 'Тайёр'),
      ('in_delivery', 'Йўлда'),
      ('delivered', 'Етказилди'),
      ('rejected', 'Рад'),
      // Мижоз бекор қилгани — CF `cancelled` хабарини ҳам ёзади, аввал
      // филтрда йўқ эди.
      ('cancelled', 'Бекор'),
      // Статуссиз: курьер етиб келди, тўлов/йиғим чеки, ресторан.
      (kOrderNewsOtherFilter, 'Бошқа'),
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
                color: _statusFilter == f.$1 ? AppColors.primaryText : Colors.grey.shade700,
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
  const _ResponsiveGrid({required this.items});

  final List<NewsItem> items;

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
          itemBuilder: (_, i) => _OrderNewsCard(item: items[i]),
        );
      },
    );
  }
}

class _OrderNewsCard extends StatelessWidget {
  const _OrderNewsCard({required this.item});

  final NewsItem item;

  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final typeLabel = orderNewsTypeLabel(item);
    final status = orderNewsStatusLabel(item);
    final phone = item.targetUserId.isNotEmpty ? item.targetUserId : '—';
    final orderId = item.orderId.isNotEmpty
        ? (item.orderId.length > 10
            ? '${item.orderId.substring(0, 10)}…'
            : item.orderId)
        : '—';

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
                      color: AppColors.primaryText,
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
                  Text('📱 $phone',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                  Text('🆔 $orderId',
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
                    '⭐ ${item.priority}',
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
