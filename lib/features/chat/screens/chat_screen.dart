import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.targetPhone,
  });

  final String targetPhone;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatController>(
      create: (ctx) => ChatController(
        repo: ctx.read<ChatRepository>(),
        chatId: phoneDigits(targetPhone),
        isAdmin: false, // Мобил: ҳар доим false. Admin web — chat_support_screen.dart
      ),
      child: const _ChatView(),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  static const _green = AppColors.primaryDark;

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
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
    final title = ctrl.isAdmin ? '💬 Мижоз чати' : '💬 Админ билан чат';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
                final messages = snap.data!;
                if (messages.isEmpty) {
                  return const Center(child: Text('Ҳозирча хабарлар йўқ'));
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
                        hintText: 'Хабар ёзинг...',
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
                      foregroundColor: Colors.white,
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
