import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';
import '../services/admin_auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// Р§Р°С‚-Т›СћР»Р»aР±-Т›СѓРІРІaС‚Р»aС€ вЂ” Admin web.
///
/// Р§aРїРґa С‡aС‚Р»aСЂ СЂСћР№С…aС‚Рё (recent first), СћРЅРіРґР° С‚Р°РЅР»aРЅРіaРЅ С‡aС‚РЅРёРЅРі РјaС‚РЅР»aСЂРё.
/// Yangi xabar bor Р±СћР»СЃa, badge Р±РёР»aРЅ РєСћСЂСЃaС‚РёР»aРґРё.
class ChatSupportScreen extends StatefulWidget {
  const ChatSupportScreen({super.key});

  @override
  State<ChatSupportScreen> createState() => _ChatSupportScreenState();
}

class _ChatSupportScreenState extends State<ChatSupportScreen> {
  String? _selectedChatId;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 900;

    return Column(children: [
      _header(),
      Expanded(
        child: Row(children: [
          // Р§aС‚Р»aСЂ СЂСћР№С…aС‚Рё
          SizedBox(
            width: isWide ? 360 : (_selectedChatId == null ? media.size.width : 0),
            child: isWide || _selectedChatId == null
                ? _ChatsList(
                    selectedId: _selectedChatId,
                    onSelect: (id) =>
                        setState(() => _selectedChatId = id),
                  )
                : const SizedBox.shrink(),
          ),
          // РўР°РЅР»aРЅРіaРЅ С‡aС‚
          if (isWide) const VerticalDivider(width: 1),
          if (isWide || _selectedChatId != null)
            Expanded(
              child: _selectedChatId == null
                  ? _emptyChatHint()
                  : _ChatView(
                      chatId: _selectedChatId!,
                      onBack: !isWide
                          ? () => setState(() => _selectedChatId = null)
                          : null,
                    ),
            ),
        ]),
      ),
    ]);
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
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: const [
        Text('рџ’¬ Р§aС‚-Т›СћР»Р»aР±-Т›СѓРІРІaС‚Р»aС€',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _emptyChatHint() {
    return Container(
      color: AppColors.scaffold,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chat_bubble_outline,
                size: 50, color: Colors.blue.shade300),
          ),
          const SizedBox(height: 16),
          Text('Р§aС‚ С‚Р°РЅР»aРЅРі',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text('Р§aРїРґaРіРё С„РѕР№РґaР»aРЅСѓРІС‡РёР»aСЂРґaРЅ Р±РёСЂРёРЅРё Р±РѕСЃРёРЅРі',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// CHATS LIST
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

class _ChatsList extends StatelessWidget {
  const _ChatsList({required this.selectedId, required this.onSelect});
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('support_chats')
            .orderBy('updatedAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('РҐР°С‚oР»РёРє: ${snap.error}',
                        style: const TextStyle(color: Colors.red))));
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_outlined,
                      size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Р§aС‚ Р№Рѕq',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600)),
                ]),
              ),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (_, i) {
              final doc = docs[i];
              return _ChatTile(
                doc: doc,
                selected: doc.id == selectedId,
                onTap: () => onSelect(doc.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.doc,
    required this.selected,
    required this.onTap,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final phone = doc.id; // chatId == userPhone
    final lastMessage = (d['lastMessage'] ?? '') as String;
    final lastFromAdmin = (d['lastFromAdmin'] ?? false) as bool;
    final updatedAt = (d['updatedAt'] as Timestamp?)?.toDate();
    final timeStr = updatedAt != null
        ? DateFormat('dd.MM HH:mm').format(updatedAt)
        : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.primary.withValues(alpha: 0.05) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: const Icon(Icons.person,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('+$phone',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (lastFromAdmin)
                      Icon(Icons.done_all,
                          size: 14, color: Colors.blue.shade400),
                    if (lastFromAdmin) const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lastMessage.isEmpty ? '(Р‘СћС€ xР°Р±aСЂ)' : lastMessage,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: lastMessage.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// CHAT VIEW
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

class _ChatView extends StatefulWidget {
  const _ChatView({required this.chatId, this.onBack});
  final String chatId;
  final VoidCallback? onBack;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      // Client Firestore rules Р±РёР»Р°РЅ С‡Р°Т›РёСЂРёТ›Р»Р°СЂ Р№РёСЂРёРє ТіРѕР»Р»Р°СЂРґР° СЂР°Рґ СЌС‚РёР»Р°РґРё вЂ”
      // Admin SDK callable РѕСЂТ›Р°Р»Рё С‘Р·Р°РјРёР· (admin role СЃРµСЂРІРµСЂРґР° С‚РµРєС€РёСЂРёР»Р°РґРё).
      final auth = context.read<AdminAuthService>();
      final fn =
          FirebaseFunctions.instance.httpsCallable('sendSupportChatReply');
      await fn.call(<String, dynamic>{
        'chatId': widget.chatId,
        'text': text,
        'adminPhone': auth.phone ?? '',
      });
      _msgCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ChatRepository>();
    return Column(children: [
      _topBar(),
      Expanded(
        child: Container(
          color: AppColors.scaffold,
          child: StreamBuilder<List<ChatMessage>>(
            stream: repo.watchMessages(widget.chatId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final msgs = snap.data ?? const <ChatMessage>[];
              if (msgs.isEmpty) {
                return Center(
                  child: Text('Р‘Сѓ С‡aС‚ Р±СћС€',
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade500)),
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollCtrl.hasClients) {
                  _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                }
              });
              final staffDigits = context.read<AdminAuthService>().phoneDigits ?? '';
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                itemCount: msgs.length,
                itemBuilder: (_, i) => _MessageBubble(
                  msg: msgs[i],
                  staffDigits: staffDigits,
                ),
              );
            },
          ),
        ),
      ),
      _inputBar(),
    ]);
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        if (widget.onBack != null)
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child:
              const Icon(Icons.person, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('+${widget.chatId}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Р¤РѕР№РґР°Р»aРЅСѓРІС‡Рё',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ]),
      ]),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Р–aРІoР± С‘Р·РёРЅРі...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.staffDigits});
  final ChatMessage msg;
  /// Р–РѕСЂРёР№ Р°РґРјРёРЅ СЃРµСЃСЃРёСЏСЃРё (СЂР°Т›Р°РјР»Р°СЂ) вЂ” client С…Р°Р±Р°СЂР»Р°СЂРёРґР° `fromAdmin` false.
  final String staffDigits;

  @override
  Widget build(BuildContext context) {
    final staff = phoneDigits(staffDigits);
    final isOutgoing = msg.fromAdmin ||
        (staff.isNotEmpty && phoneDigits(msg.fromPhone) == staff);
    final time = msg.createdAt != null
        ? DateFormat('HH:mm').format(msg.createdAt!)
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOutgoing ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isOutgoing ? 14 : 2),
                  bottomRight: Radius.circular(isOutgoing ? 2 : 14),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.text,
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                isOutgoing ? Colors.white : Colors.black87)),
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(time,
                          style: TextStyle(
                              fontSize: 10,
                              color: isOutgoing
                                  ? Colors.white70
                                  : Colors.grey.shade500)),
                      if (isOutgoing) ...[
                        const SizedBox(width: 4),
                        Icon(
                            msg.read
                                ? Icons.done_all
                                : Icons.done,
                            size: 12,
                            color: Colors.white70),
                      ],
                    ]),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}
