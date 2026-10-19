import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../models/news_read_state.dart';
import '../../../models/order_news_group.dart';
import '../../../repositories/news_repository.dart';
import '../widgets/news_delete_button.dart';
import 'order_news_detail_screen.dart';

/// Буюртма хабарлари — ҳар буюртма алоҳида карта.
class OrderNewsTab extends StatefulWidget {
  const OrderNewsTab({
    super.key,
    this.onMarkedRead,
    this.readState = NewsReadState.unknown,
  });

  final VoidCallback? onMarkedRead;

  /// Экранга кирилгандаги ўқилганлик ҳолати — «янги» карталарни ажратади.
  final NewsReadState readState;

  @override
  State<OrderNewsTab> createState() => _OrderNewsTabState();
}

class _OrderNewsTabState extends State<OrderNewsTab>
    with AutomaticKeepAliveClientMixin {
  static const _orange = AppColors.primary;

  // Оқим БИР марта очилади: аввал `build` ичида ҳар сафар янгиси очилар ва
  // «Хабарлар» экрани badge сабабли қайта чизилганда рўйхат айлана (spinner)
  // билан «милтиллар» эди (эга, 2026-10-19).
  Stream<List<NewsItem>>? _stream;
  String _uid = '';
  Set<String> _hidden = <String>{};
  StreamSubscription<Set<String>>? _dismissedSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (!mounted) return;
    final repo = context.read<NewsRepository>();
    final stream = repo.watchOrderNews(userId: uid, limit: 50);
    // Ўчирилган хабарлар сервердан (барча қурилмада бир хил); янги ўчириш дарров, тўплам фақат ўсади.
    _dismissedSub = repo.watchDismissedIds(uid).listen((ids) {
      if (mounted) setState(() => _hidden = {..._hidden, ...ids});
    });
    setState(() {
      _uid = uid;
      _stream = stream;
    });
  }

  @override
  void dispose() {
    _dismissedSub?.cancel();
    super.dispose();
  }

  Future<void> _deleteGroup(OrderNewsGroup g) async {
    final ids = g.messages.map((m) => m.id).toList();
    setState(() => _hidden = {..._hidden, ...ids});
    await context.read<NewsRepository>().dismissNews(_uid, ids);
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
      // CF `onOrderUpdate` бу статусларни ҳам ёзади — аввал мижозга хом
      // `in_delivery` / `cancelled` чиқарди.
      case 'in_delivery':
        return context.tr('order_status_in_delivery');
      case 'cancelled':
        return context.tr('order_status_cancelled');
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stream = _stream;
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<NewsItem>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError && !snap.hasData) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final visible = (snap.data ?? const <NewsItem>[])
            .where((n) => !_hidden.contains(n.id));
        final groups = OrderNewsGroup.fromItems(visible.toList());
        if (groups.isEmpty) return _emptyState();
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _groupCard(context, groups[i]),
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
    final unreadCount =
        g.messages.where((m) => widget.readState.isUnread(m.createdAt)).length;
    final unread = unreadCount > 0;

    return Material(
      key: ValueKey('order-news-${g.orderId.isEmpty ? latest.id : g.orderId}'),
      // Ўқилмаган — жирний (қалин) ёзув, ўқилган — оддий ёзув (эга, 2026-10-19).
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                  g.orderType == 'restaurant'
                      ? Icons.restaurant
                      : Icons.bakery_dining,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.moduleLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${g.messages.length} хабар · сўнгги: $status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      latest.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
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
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              NewsDeleteButton(onDelete: () => _deleteGroup(g)),
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
