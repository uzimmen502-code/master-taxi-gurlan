import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../data/deal_chat_repository.dart';
import 'deal_chat_screen.dart';

/// «Буюртма чатлари» — харидор ва сотувчи учун битта рўйхат (кимлиги қаторда ёзилади).
class DealChatsScreen extends StatefulWidget {
  const DealChatsScreen({super.key, required this.myUid, this.repository});

  final String myUid;
  final DealChatRepository? repository;

  @override
  State<DealChatsScreen> createState() => _DealChatsScreenState();
}

class _DealChatsScreenState extends State<DealChatsScreen> {
  late final DealChatRepository _repo = widget.repository ?? DealChatRepository();
  late Stream<List<DealChat>> _stream = _repo.watchMyChats(widget.myUid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('deal_chats_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: StreamBuilder<List<DealChat>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return LoadErrorView(
              error: snap.error!,
              onRetry: () => setState(() => _stream = _repo.watchMyChats(widget.myUid)),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final chats = snap.data!;
          if (chats.isEmpty) {
            return Center(child: Text(context.tr('deal_chats_empty')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => DealChatTile(
              chat: chats[i],
              myUid: widget.myUid,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DealChatScreen(
                    chatId: chats[i].id,
                    myUid: widget.myUid,
                    repository: widget.repository,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Рўйхат қатори: маҳсулот расми ва номи, қарши томон (Сотувчи/Харидор), охирги хабар, вақт,
/// ўқилмаганлар сони.
class DealChatTile extends StatelessWidget {
  const DealChatTile({super.key, required this.chat, required this.myUid, required this.onTap});

  final DealChat chat;
  final String myUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unreadFor(myUid);
    final other = context.tr(chat.isSeller(myUid) ? 'deal_chat_role_buyer' : 'deal_chat_role_seller');
    final last =
        chat.lastFrom == myUid ? '${context.tr('deal_chat_you')} ${chat.lastMessage}' : chat.lastMessage;
    final bold = unread > 0 ? FontWeight.bold : FontWeight.normal;
    return Material(
      key: ValueKey('deal-chat-tile-${chat.id}'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: chat.productPhoto.isEmpty
                      ? ColoredBox(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.inventory_2_outlined, color: Colors.grey))
                      : Image.network(chat.productPhoto,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.inventory_2_outlined, color: Colors.grey))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.productTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: bold)),
                    const SizedBox(height: 2),
                    Text(other, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: bold, color: Colors.grey.shade800)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (chat.lastAt != null)
                    Text(_shortTime(chat.lastAt!),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      key: ValueKey('deal-chat-unread-${chat.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortTime(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} $hm';
  }
}
