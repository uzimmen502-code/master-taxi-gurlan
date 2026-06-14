import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../chat/screens/chat_screen.dart';
import 'dialog_news_detail_screen.dart';

/// Мурожаатлар: admin_news (диалог), support чат, ҳайдовчи аризаси.
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key, this.onMarkedRead});

  final VoidCallback? onMarkedRead;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  static const _green = AppColors.primaryDark;

  Future<String> _uid() async {
    final prefs = await SharedPreferences.getInstance();
    return canonicalPhoneId(prefs.getString('user_phone') ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final newsRepo = context.read<NewsRepository>();
    final chatRepo = context.read<ChatRepository>();
    final driverRepo = context.read<DriverRepository>();

    return FutureBuilder<String>(
      future: _uid(),
      builder: (ctx, uidSnap) {
        final uid = uidSnap.data ?? '';
        if (uid.length < 9) {
          return const Center(child: Text('Телефон рақамини профилда киритинг'));
        }

        return StreamBuilder<List<NewsItem>>(
          stream: newsRepo.watchDialogNews(userId: uid, limit: 80),
          builder: (ctx, newsSnap) {
            return StreamBuilder<bool>(
              stream: chatRepo.watchUnreadFromAdmin(uid),
              builder: (ctx, chatUnreadSnap) {
                return StreamBuilder<Map<String, dynamic>?>(
                  stream: driverRepo.watchMyDriverRequest(uid),
                  builder: (ctx, driverSnap) {
                    if (newsSnap.connectionState == ConnectionState.waiting &&
                        !newsSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (newsSnap.hasError) {
                      return Center(child: Text('Хатолик: ${newsSnap.error}'));
                    }

                    final chatUnread = chatUnreadSnap.data ?? false;
                    final groups =
                        MessageThreadGroup.fromDialogNews(newsSnap.data ?? []);
                    final driverGroup = MessageThreadGroup.fromDriverRequest(
                      driverSnap.data,
                      uid,
                    );

                    final rows = <_InboxRow>[];
                    rows.add(
                      _InboxRow.supportChat(unread: chatUnread),
                    );
                    if (driverGroup != null) {
                      rows.add(_InboxRow.driver(driverGroup));
                    }
                    for (final g in groups) {
                      rows.add(_InboxRow.dialog(g));
                    }

                    if (rows.length == 1 &&
                        !chatUnread &&
                        (newsSnap.data ?? []).isEmpty &&
                        driverSnap.data == null) {
                      return _emptyState();
                    }

                    rows.sort((a, b) => b.sortTime.compareTo(a.sortTime));

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _rowTile(context, uid, rows[i]),
                    );
                  },
                );
              },
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
          Icon(Icons.inbox_outlined, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text(
            'Хабарлар йўқ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Мурожаат жавоби шу йерда кўринади',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(BuildContext context, String uid, _InboxRow row) {
    switch (row.kind) {
      case _InboxRowKind.supportChat:
        return _supportChatCard(context, uid, row.unread);
      case _InboxRowKind.driver:
        return _driverCard(context, row.group!);
      case _InboxRowKind.dialog:
        return _dialogCard(context, row.group!);
    }
  }

  Widget _supportChatCard(BuildContext context, String uid, bool unread) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(targetPhone: uid),
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
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.support_agent, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '💬 Админ билан чат',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unread ? 'Янги жавоб бор' : 'Ёзишмалар тарихи',
                      style: TextStyle(
                        fontSize: 12,
                        color: unread ? Colors.red.shade700 : Colors.grey.shade600,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverCard(BuildContext context, MessageThreadGroup g) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.local_taxi, color: Colors.blue),
        ),
        title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          g.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _shortDate(g.lastUpdate),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ),
    );
  }

  Widget _dialogCard(BuildContext context, MessageThreadGroup g) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DialogNewsDetailScreen(group: g),
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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${g.messages.length} хабар · ${g.subtitle}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _shortDate(g.lastUpdate),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
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

enum _InboxRowKind { supportChat, driver, dialog }

class _InboxRow {
  _InboxRow._({
    required this.kind,
    this.group,
    this.unread = false,
    required this.sortTime,
  });

  factory _InboxRow.supportChat({required bool unread}) => _InboxRow._(
        kind: _InboxRowKind.supportChat,
        unread: unread,
        sortTime: unread ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory _InboxRow.driver(MessageThreadGroup g) => _InboxRow._(
        kind: _InboxRowKind.driver,
        group: g,
        sortTime: g.lastUpdate,
      );

  factory _InboxRow.dialog(MessageThreadGroup g) => _InboxRow._(
        kind: _InboxRowKind.dialog,
        group: g,
        sortTime: g.lastUpdate,
      );

  final _InboxRowKind kind;
  final MessageThreadGroup? group;
  final bool unread;
  final DateTime sortTime;
}
