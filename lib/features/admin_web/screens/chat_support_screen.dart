import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../../repositories/chat_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_delete_record_service.dart';
import '../../../core/theme/app_theme.dart';

/// Чат-қўллaб-қуввaтлaш — Admin web.
///
/// Чaпдa чaтлaр рўйхaти (recent first), ўнгда танлaнгaн чaтнинг мaтнлaри.
/// Yangi xabar bor бўлсa, badge билaн кўрсaтилaди.
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
          // Чaтлaр рўйхaти
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
          // Танлaнгaн чaт
          if (isWide) const VerticalDivider(width: 1),
          if (isWide || _selectedChatId != null)
            Expanded(
              child: _selectedChatId == null
                  ? _emptyChatHint()
                  : SupportChatView(
                      chatId: _selectedChatId!,
                      onBack: !isWide
                          ? () => setState(() => _selectedChatId = null)
                          : null,
                      onChatDeleted: () =>
                          setState(() => _selectedChatId = null),
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
        Text('💬 Чaт-қўллaб-қуввaтлaш',
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
          Text('Чaт танлaнг',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text('Чaпдaги фойдaлaнувчилaрдaн бирини босинг',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// CHATS LIST
// ═════════════════════════════════════════════════════════════════════

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
                    child: Text('Хатoлик: ${snap.error}',
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
                  Text('Чат ёқ',
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
    // Сайдбар badge'и билан бир хил қоида (`admin_shell.dart`).
    final awaiting = d.containsKey('awaitingAdmin')
        ? d['awaitingAdmin'] == true
        : !lastFromAdmin;
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
                color: AppColors.primaryText, size: 22),
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
                    if (awaiting) ...[
                      Icon(Icons.circle, size: 9, color: Colors.red.shade400),
                      const SizedBox(width: 6),
                    ],
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
                        lastMessage.isEmpty ? '(Бўш xабaр)' : lastMessage,
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

// ═════════════════════════════════════════════════════════════════════
// CHAT VIEW
// ═════════════════════════════════════════════════════════════════════

/// Танланган чат (хабарлар + жавоб + ўчириш). Алоҳида синф — виджет тестида
/// `ChatRepository` / `AdminDeleteRecordService` Provider'и билан ишга тушади.
@visibleForTesting
class SupportChatView extends StatefulWidget {
  const SupportChatView(
      {super.key, required this.chatId, this.onBack, this.onChatDeleted});
  final String chatId;
  final VoidCallback? onBack;

  /// Чат сервер томонидан тўлиқ ўчирилгандан кейин (танловни тозалаш учун).
  final VoidCallback? onChatDeleted;

  @override
  State<SupportChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<SupportChatView> {
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
      // Client Firestore rules билан чақириқлар йирик ҳолларда рад этилади —
      // Admin SDK callable орқали ёзамиз (admin role серверда текширилади).
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
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Битта хабарни ўчириш: сервер (callable) ўчиради, матнсиз нусха audit'да қолади.
  Future<void> _deleteMessage(ChatMessage msg) async {
    final ok = await _confirm(
      'Хабар ўчирилсинми?',
      'Хабар чатдан ТЎЛИҚ ўчади (мижоз ҳам кўрмайди), қайтариб бўлмайди. '
          'Матни audit журналига ёзилмайди.',
    );
    if (!ok || !mounted) return;
    final service = context.read<AdminDeleteRecordService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.deleteSupportMessage(widget.chatId, msg.id);
      messenger.showSnackBar(const SnackBar(
        backgroundColor: AppColors.button,
        content:
            Text('Хабар ўчирилди', style: TextStyle(color: AppColors.onPrimary)),
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    }
  }

  /// Бутун чатни (барча хабарлар билан) ўчириш.
  Future<void> _deleteChat() async {
    final ok = await _confirm(
      'Чат ўчирилсинми?',
      '+${widget.chatId} билан бутун ёзишма ТЎЛИҚ ўчади — мижоз ўз '
          'иловасида ҳам кўрмайди. Қайтариб бўлмайди; фақат санаш маълумоти '
          '(матнсиз) audit журналида қолади.',
    );
    if (!ok || !mounted) return;
    final service = context.read<AdminDeleteRecordService>();
    final messenger = ScaffoldMessenger.of(context);
    final onDeleted = widget.onChatDeleted;
    try {
      final res = await service.deleteSupportChat(widget.chatId);
      if (res.partial) {
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Чат катта: қолган хабарларни ўчириш учун яна босинг'),
        ));
        return;
      }
      messenger.showSnackBar(const SnackBar(
        backgroundColor: AppColors.button,
        content:
            Text('Чат ўчирилди', style: TextStyle(color: AppColors.onPrimary)),
      ));
      onDeleted?.call();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
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
                  child: Text('Бу чaт бўш',
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
                  onDelete: () => _deleteMessage(msgs[i]),
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
              const Icon(Icons.person, color: AppColors.primaryText, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('+${widget.chatId}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Фойдалaнувчи',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600)),
            ]),
        const Spacer(),
        IconButton(
          key: const ValueKey('chat-delete'),
          tooltip: 'Чатни ўчириш',
          onPressed: _deleteChat,
          icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
        ),
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
              hintText: 'Жaвoб ёзинг...',
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
                      strokeWidth: 2, color: AppColors.onPrimary))
              : const Icon(Icons.send),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.msg, required this.staffDigits, this.onDelete});
  final ChatMessage msg;

  /// Хабарни ўчириш (тасдиқ диалоги экран томонида).
  final VoidCallback? onDelete;
  /// Жорий админ сессияси (рақамлар) — client хабарларида `fromAdmin` false.
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
                                isOutgoing ? AppColors.onPrimary : Colors.black87)),
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(time,
                          style: TextStyle(
                              fontSize: 10,
                              color: isOutgoing
                                  ? AppColors.onPrimary.withValues(alpha: 0.7)
                                  : Colors.grey.shade500)),
                      if (isOutgoing) ...[
                        const SizedBox(width: 4),
                        Icon(
                            msg.read
                                ? Icons.done_all
                                : Icons.done,
                            size: 12,
                            color: AppColors.onPrimary.withValues(alpha: 0.7)),
                      ],
                      if (onDelete != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          key: ValueKey('msg-delete-${msg.id}'),
                          onTap: onDelete,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.delete_outline,
                                size: 15,
                                color: isOutgoing
                                    ? AppColors.onPrimary.withValues(alpha: 0.8)
                                    : Colors.red.shade300),
                          ),
                        ),
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
