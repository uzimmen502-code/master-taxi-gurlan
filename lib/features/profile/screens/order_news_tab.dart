import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../models/order_news_group.dart';
import '../../../repositories/news_repository.dart';
import 'order_news_detail_screen.dart';

/// Буюртма хабарлари — ҳар буюртма алоҳида карта.
class OrderNewsTab extends StatefulWidget {
  const OrderNewsTab({super.key, this.onMarkedRead});

  final VoidCallback? onMarkedRead;

  @override
  State<OrderNewsTab> createState() => _OrderNewsTabState();
}

class _OrderNewsTabState extends State<OrderNewsTab> {
  static const _orange = AppColors.primary;

  Future<String> _uid() async {
    final prefs = await SharedPreferences.getInstance();
    return canonicalPhoneId(prefs.getString('user_phone') ?? '');
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'delivered':
        return 'Етказилди';
      case 'rejected':
        return 'Рад';
      case 'new':
        return 'Юборилди';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NewsRepository>();
    return FutureBuilder<String>(
      future: _uid(),
      builder: (ctx, uidSnap) {
        final uid = uidSnap.data ?? '';
        return StreamBuilder<List<NewsItem>>(
          stream: repo.watchOrderNews(userId: uid, limit: 50),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Хатолик: ${snap.error}'));
            }
            final groups = OrderNewsGroup.fromItems(snap.data ?? const []);
            if (groups.isEmpty) return _emptyState();
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _groupCard(context, groups[i]),
            );
          },
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text('Буюртма хабарлари йўқ',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text('Статус ўзгарса шу йерда кўринади',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, OrderNewsGroup g) {
    final latest = g.latestMessage;
    final status = _statusLabel(latest.orderStatus);
    final date = _shortDate(g.lastUpdate);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderNewsDetailScreen(group: g),
            ),
          );
          widget.onMarkedRead?.call();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  g.orderType == 'food' ? Icons.restaurant : Icons.bakery_dining,
                  color: _orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.moduleLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${g.messages.length} хабар · сўнгги: $status',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      latest.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(date,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime t) {
    return '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
