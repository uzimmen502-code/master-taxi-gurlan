import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';
import '../../../models/news_read_state.dart';
import '../inbox_hide_keys.dart';
import '../widgets/news_delete_button.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../chat/screens/chat_screen.dart';
import 'dialog_news_detail_screen.dart';

/// Мурожаатлар: admin_news (диалог), support чат, ҳайдовчи аризаси.
class MessagesTab extends StatefulWidget {
  const MessagesTab({
    super.key,
    this.onMarkedRead,
    this.readState = NewsReadState.unknown,
  });

  final VoidCallback? onMarkedRead;

  /// Экранга кирилгандаги ўқилганлик ҳолати — «янги» карталарни ажратади.
  final NewsReadState readState;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab>
    with AutomaticKeepAliveClientMixin {
  static const _green = AppColors.primaryDark;

  // Оқимлар БИР марта очилади: аввал `build` ичида ҳар сафар янгилари очилар
  // ва «Хабарлар» экрани badge сабабли қайта чизилганда рўйхат айлана
  // (spinner) билан «милтиллар» эди (эга, 2026-10-19).
  bool _ready = false;
  String _uid = '';
  Set<String> _hidden = <String>{};
  StreamSubscription<Set<String>>? _dismissedSub;
  Stream<List<NewsItem>>? _newsStream;
  Stream<bool>? _chatStream;
  Stream<Map<String, dynamic>?>? _driverStream;

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
    final newsRepo = context.read<NewsRepository>();
    final chatRepo = context.read<ChatRepository>();
    final driverRepo = context.read<DriverRepository>();
    // Ўчирилган хабарлар сервердан (барча қурилмада бир хил); янги ўчириш дарров, тўплам фақат ўсади.
    if (uid.length >= 9) {
      _dismissedSub = newsRepo.watchDismissedIds(uid).listen((ids) {
        if (mounted) setState(() => _hidden = {..._hidden, ...ids});
      });
    }
    setState(() {
      _uid = uid;
      if (uid.length >= 9) {
        _newsStream = newsRepo.watchDialogNews(userId: uid, limit: 80);
        _chatStream = chatRepo.watchUnreadFromAdmin(uid);
        _driverStream = driverRepo.watchMyDriverRequest(uid);
      }
      _ready = true;
    });
  }

  /// Хато бўлса — фақат хабарлар оқимини қайта очади.
  void _retryNews() {
    final newsRepo = context.read<NewsRepository>();
    setState(() {
      _newsStream = newsRepo.watchDialogNews(userId: _uid, limit: 80);
    });
  }

  @override
  void dispose() {
    _dismissedSub?.cancel();
    super.dispose();
  }

  Future<void> _deleteGroup(MessageThreadGroup g) async {
    final ids = g.messages.map((m) => m.id).toList();
    setState(() => _hidden = {..._hidden, ...ids});
    await context.read<NewsRepository>().dismissNews(_uid, ids);
  }

  /// Ҳайдовчи аризаси картасини яшириш (ариза ҳолати ўзгарса яна чиқади) — [InboxHideKeys.driverRequest].
  Future<void> _hideKey(String key) async {
    setState(() => _hidden = {..._hidden, key});
    await context.read<NewsRepository>().dismissNews(_uid, [key]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final uid = _uid;
    if (uid.length < 9) {
      return Center(child: Text(context.tr('msgs_phone_required')));
    }

    return StreamBuilder<List<NewsItem>>(
      stream: _newsStream,
      builder: (ctx, newsSnap) {
        return StreamBuilder<bool>(
          stream: _chatStream,
          builder: (ctx, chatUnreadSnap) {
            return StreamBuilder<Map<String, dynamic>?>(
              stream: _driverStream,
              builder: (ctx, driverSnap) {
                if (newsSnap.connectionState == ConnectionState.waiting &&
                    !newsSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (newsSnap.hasError && !newsSnap.hasData) {
                  return LoadErrorView(
                    error: newsSnap.error!,
                    onRetry: _retryNews,
                  );
                }

                final chatUnread = chatUnreadSnap.data ?? false;
                final shownNews = (newsSnap.data ?? const <NewsItem>[])
                    .where((n) => !_hidden.contains(n.id))
                    .toList();
                final groups = MessageThreadGroup.fromDialogNews(shownNews);
                final driverData = driverSnap.data;
                final driverKey =
                    driverData == null ? '' : InboxHideKeys.driverRequest(driverData);
                final driverGroup = driverData == null || _hidden.contains(driverKey)
                    ? null
                    : MessageThreadGroup.fromDriverRequest(driverData, uid);

                final rows = <_InboxRow>[];
                rows.add(
                  _InboxRow.supportChat(unread: chatUnread),
                );
                if (driverGroup != null) {
                  rows.add(_InboxRow.driver(driverGroup, hideKey: driverKey));
                }
                for (final g in groups) {
                  rows.add(_InboxRow.dialog(g));
                }

                if (rows.length == 1 &&
                    !chatUnread &&
                    shownNews.isEmpty &&
                    driverGroup == null) {
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
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text(
            context.tr('no_messages'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('msgs_empty_hint'),
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
        return _driverCard(context, row.group!, row.hideKey);
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
                child: const Icon(Icons.support_agent,
                    color: AppColors.primaryText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('chat_admin_title'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unread
                          ? context.tr('msgs_new_reply')
                          : context.tr('msgs_history'),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            unread ? Colors.red.shade700 : Colors.grey.shade600,
                        fontWeight:
                            unread ? FontWeight.w600 : FontWeight.normal,
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
              // Ўчириш (эга, 2026-10-26) = ёзишмалар тарихини ўз рўйхатидан тозалаш. Қаторнинг ЎЗИ қолади:
              // у админга ёзишнинг ягона йўли (бошқа кириш фақат push орқали).
              NewsDeleteButton(
                key: const ValueKey('support-chat-clear'),
                titleKey: 'chat_clear_title',
                bodyKey: 'chat_clear_body',
                doneKey: 'chat_cleared_snack',
                onDelete: () => _hideKey(InboxHideKeys.supportChatCleared(DateTime.now())),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverCard(BuildContext context, MessageThreadGroup g, String hideKey) {
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
        title:
            Text(context.tr(g.title),
                style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          g.subtitleText(context.tr),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _shortDate(g.lastUpdate),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            // Ўчириш (эга, 2026-10-26): карта яширилади, ариза ҳолати ўзгарса яна чиқади.
            NewsDeleteButton(
              key: const ValueKey('driver-card-delete'),
              onDelete: () => _hideKey(hideKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogCard(BuildContext context, MessageThreadGroup g) {
    final unread =
        g.messages.any((m) => widget.readState.isUnread(m.createdAt));
    return Material(
      key: ValueKey('dialog-news-${g.id}'),
      // Ўқилмаган — жирний (қалин) ёзув, ўқилган — оддий ёзув (эга, 2026-10-19).
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
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
                    color: AppColors.primaryText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(g.title),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.trMsg('msgs_group_summary', params: {
                        'n': '${g.messages.length}',
                        'subtitle': g.subtitleText(context.tr),
                      }),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
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

enum _InboxRowKind { supportChat, driver, dialog }

class _InboxRow {
  _InboxRow._({
    required this.kind,
    this.group,
    this.unread = false,
    required this.sortTime,
    this.hideKey = '',
  });

  factory _InboxRow.supportChat({required bool unread}) => _InboxRow._(
        kind: _InboxRowKind.supportChat,
        unread: unread,
        sortTime:
            unread ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory _InboxRow.driver(MessageThreadGroup g, {required String hideKey}) => _InboxRow._(
        kind: _InboxRowKind.driver,
        group: g,
        sortTime: g.lastUpdate,
        hideKey: hideKey,
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

  /// Ҳайдовчи аризаси картасини яшириш калити ([InboxHideKeys.driverRequest]).
  final String hideKey;
}
