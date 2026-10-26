import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../profile/inbox_hide_keys.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.targetPhone,
    @visibleForTesting this.dismissedIds,
  });

  final String targetPhone;

  /// Тест учун: «яширилди» белгилари (`users/{uid}/dismissed_news`) ўрнига.
  final Stream<Set<String>>? dismissedIds;

  @override
  Widget build(BuildContext context) {
    final chatId = phoneDigits(targetPhone);
    // «Тарихни тозалаш» белгиси (эга, 2026-10-26: «Админ билан чат» қаторида ўчириш) — тозаланишдан олдинги
    // хабарлар кўринмайди. Провайдер йўқ бўлса (бошқа илова қисми) — тарих тўлиқ.
    Stream<Set<String>> dismissed = const Stream.empty();
    try {
      dismissed = dismissedIds ?? context.read<NewsRepository>().watchDismissedIds(chatId);
    } on ProviderNotFoundException {
      dismissed = const Stream.empty();
    }
    return ChangeNotifierProvider<ChatController>(
      create: (ctx) => ChatController(
        repo: ctx.read<ChatRepository>(),
        chatId: chatId,
        isAdmin: false, // Мобил: ҳар доим false. Admin web — chat_support_screen.dart
      ),
      child: _ChatView(dismissedIds: dismissed),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.dismissedIds});

  final Stream<Set<String>> dismissedIds;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  static const _green = AppColors.primaryDark;

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  DateTime? _clearedAt;
  StreamSubscription<Set<String>>? _dismissedSub;

  @override
  void initState() {
    super.initState();
    _dismissedSub = widget.dismissedIds.listen((ids) {
      final at = InboxHideKeys.supportChatClearedAt(ids);
      if (mounted && at != _clearedAt) setState(() => _clearedAt = at);
    }, onError: (Object _) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = context.read<ChatController>();
      if (!ctrl.isAdmin) {
        context.read<ChatRepository>().markUserRead(ctrl.chatId);
      }
    });
  }

  @override
  void dispose() {
    _dismissedSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ctrl = context.read<ChatController>();
    final text = _msgCtrl.text;
    if (text.trim().isEmpty) return;
    _msgCtrl.clear();
    await ctrl.send(text);
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted || !_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<ChatController>();
    final title = ctrl.isAdmin
        ? context.tr('chat_customer_title')
        : context.tr('chat_admin_title');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: ctrl.messages,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snap.data!
                    .where((m) => InboxHideKeys.visibleAfterClear(m.createdAt, _clearedAt))
                    .toList();
                if (messages.isEmpty) {
                  return Center(child: Text(context.tr('chat_empty')));
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    // Client SDK `fromAdmin` ёза олмайди — "меники"ни телефон бўйича.
                    final my = ctrl.myPhone;
                    final mine = my.isNotEmpty
                        ? phoneDigits(m.fromPhone) == my
                        : !m.fromAdmin;
                    return MessageBubble(message: m, isMine: mine);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: context.tr('chat_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: AppColors.onPrimary,
                    ),
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
