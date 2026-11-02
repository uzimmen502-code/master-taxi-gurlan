import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../profile/inbox_hide_keys.dart';
import '../controllers/chat_controller.dart';
import '../widgets/chat_composer.dart';
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
  final _msgCtrl = TextEditingController();
  DateTime? _clearedAt;
  StreamSubscription<Set<String>>? _dismissedSub;
  late Stream<List<ChatMessage>> _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = context.read<ChatController>().messages;
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
    super.dispose();
  }

  /// Юборилмаса — матн майдонга қайтади ва тушунарли хабар (аввал хато жимгина йўқоларди).
  Future<void> _send() async {
    final ctrl = context.read<ChatController>();
    final text = _msgCtrl.text;
    if (text.trim().isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() => _sending = true);
    try {
      await ctrl.send(text);
    } catch (e) {
      debugPrint('[ChatScreen] send: $e');
      if (!mounted) return;
      if (_msgCtrl.text.isEmpty) _msgCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('chat_send_failed'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<ChatController>();
    final c = context.ava;
    final title = ctrl.isAdmin
        ? context.tr('chat_customer_title')
        : context.tr('inbox_support_title');

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                // Аввал хато бўлса чексиз айланиб турарди.
                if (snap.hasError && !snap.hasData) {
                  return _ChatError(
                    onRetry: () => setState(() => _messages = ctrl.reloadMessages()),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snap.data!
                    .where((m) => InboxHideKeys.visibleAfterClear(m.createdAt, _clearedAt))
                    .toList();
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.tr('chat_empty'),
                          textAlign: TextAlign.center, style: AvaText.body.copyWith(color: c.ink2)),
                    ),
                  );
                }
                final rows = withDaySeparators<ChatMessage>(messages, (m) => m.createdAt);
                // Тескари рўйхат — чат энг янги хабардан (пастдан) очилади.
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[rows.length - 1 - i];
                    if (r is ChatDay) return ChatDaySeparator(day: r.day);
                    final m = r as ChatMessage;
                    // Client SDK `fromAdmin` ёза олмайди — "меники"ни телефон бўйича.
                    final my = ctrl.myPhone;
                    final mine = my.isNotEmpty
                        ? phoneDigits(m.fromPhone) == my
                        : !m.fromAdmin;
                    return MessageBubble(key: ValueKey('chat-msg-${m.id}'), message: m, isMine: mine);
                  },
                );
              },
            ),
          ),
          ChatComposer(
            controller: _msgCtrl,
            onSend: _send,
            sending: _sending,
            hintKey: 'chat_hint',
            inputKey: const ValueKey('support-chat-input'),
            sendKey: const ValueKey('support-chat-send'),
          ),
        ],
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: c.ink3),
            const SizedBox(height: 10),
            Text(context.tr('chat_load_failed'),
                key: const ValueKey('chat-load-failed'),
                textAlign: TextAlign.center,
                style: AvaText.body.copyWith(color: c.inkRow)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: Text(context.tr('inbox_retry'))),
          ],
        ),
      ),
    );
  }
}
