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
import '../services/support_chat_archive.dart';
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

  /// «Архивланган» кўриниши: рўйхатда фақат архивдаги чатлар (қайта очиш/ўчириш талаби учун).
  bool _showArchived = false;

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
                    showArchived: _showArchived,
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
                  : _SelectedChat(
                      key: ValueKey('chat-$_selectedChatId'),
                      chatId: _selectedChatId!,
                      onBack: !isWide
                          ? () => setState(() => _selectedChatId = null)
                          : null,
                      // Архивга олингач/чиқарилгач чат шу рўйхатдан кетади — танловни тозалаймиз.
                      onChatClosed: () =>
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
      child: Row(children: [
        const Text('💬 Чaт-қўллaб-қуввaтлaш',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        FilterChip(
          key: const ValueKey('chats-archived-toggle'),
          avatar: const Icon(Icons.inventory_2_outlined, size: 16),
          label: const Text('Архивланган'),
          selected: _showArchived,
          onSelected: (v) => setState(() {
            _showArchived = v;
            _selectedChatId = null;
          }),
        ),
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

/// Танланган чат: `support_chats/{id}` ҳужжатини кузатиб, архивда ёки йўқлигини [SupportChatView]га беради
/// (янги хабар чатни ўзи қайта очади — тугма шунга мос ўзгаради).
class _SelectedChat extends StatelessWidget {
  const _SelectedChat({
    super.key,
    required this.chatId,
    required this.onChatClosed,
    this.onBack,
  });
  final String chatId;
  final VoidCallback onChatClosed;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('support_chats')
          .doc(chatId)
          .snapshots(),
      builder: (ctx, snap) {
        final archived = snap.data?.data() != null &&
            isSupportChatArchived(snap.data!.data()!);
        return SupportChatView(
          chatId: chatId,
          archived: archived,
          onBack: onBack,
          onArchiveChanged: onChatClosed,
          onChatDeleted: onChatClosed,
        );
      },
    );
  }
}

class _ChatsList extends StatelessWidget {
  const _ChatsList({
    required this.selectedId,
    required this.onSelect,
    required this.showArchived,
  });
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool showArchived;

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
          // Архивдаги чат (янги фаоллик бўлмаса) асосий рўйхатда йўқ; «Архивланган» филтрида — фақат шулар.
          final docs = (snap.data?.docs ?? const [])
              .where((d) => isSupportChatArchived(d.data()) == showArchived)
              .toList();
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_outlined,
                      size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(showArchived ? 'Архивда чат ёқ' : 'Чат ёқ',
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

/// Танланган чат (хабарлар + жавоб + архивга олиш). Алоҳида синф — виджет тестида
/// `ChatRepository` / `AdminDeleteRecordService` Provider'и билан ишга тушади.
///
/// Мижоз ёзишмаси админ томонидан ЎЧИРИЛМАЙДИ (эга, 2026-10-20): алоҳида хабарни ўчириш йўқ, чат — «Архивга олиш».
/// Ҳақиқий ўчириш фақат superadmin учун, алоҳида менюда, шахсий маълумотни ўчириш талаби бўйича.
@visibleForTesting
class SupportChatView extends StatefulWidget {
  const SupportChatView({
    super.key,
    required this.chatId,
    this.archived = false,
    this.onBack,
    this.onChatDeleted,
    this.onArchiveChanged,
  });
  final String chatId;
  final VoidCallback? onBack;

  /// Чат ҳозир архивдами ([isSupportChatArchived]) — тугма «Архивга олиш» ёки «Архивдан чиқариш».
  final bool archived;

  /// Чат сервер томонидан тўлиқ ўчирилгандан кейин (танловни тозалаш учун).
  final VoidCallback? onChatDeleted;

  /// Чат архивга олингач / архивдан чиқарилгач (танловни тозалаш учун).
  final VoidCallback? onArchiveChanged;

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

  /// Чатни архивга олиш / архивдан чиқариш (қайтариладиган амал — тасдиқ диалоги йўқ). Сервер: `adminArchiveSupportChat`.
  /// Чат ўчмайди, мижоз ўз иловасида ҳамма хабарни кўради; янги хабар келса чат ўзи қайта очилади.
  Future<void> _setArchived(bool archived) async {
    final service = context.read<AdminDeleteRecordService>();
    final messenger = ScaffoldMessenger.of(context);
    final onChanged = widget.onArchiveChanged;
    try {
      await service.archiveSupportChat(widget.chatId, archived: archived);
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.button,
        content: Text(archived ? 'Чат архивга олинди' : 'Чат архивдан чиқарилди',
            style: const TextStyle(color: AppColors.onPrimary)),
      ));
      onChanged?.call();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    }
  }

  /// ШАХСИЙ МАЪЛУМОТНИ ЎЧИРИШ (мижоз талаби бўйича) — фақат superadmin, чат аввал архивга олинган бўлиши шарт.
  /// Сабаб (камида 10 белги) ва тасдиқ белгиси мажбурий; сервер (`adminDeleteRecord`) ҳаммасини яна текширади.
  Future<void> _erasePersonalData() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _EraseDialog(chatId: widget.chatId),
    );
    if (reason == null || !mounted) return;
    final service = context.read<AdminDeleteRecordService>();
    final messenger = ScaffoldMessenger.of(context);
    final onDeleted = widget.onChatDeleted;
    try {
      final res = await service.eraseSupportChat(widget.chatId, reason: reason);
      if (res.partial) {
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Чат катта: қолган хабарларни ўчириш учун яна босинг'),
        ));
        return;
      }
      messenger.showSnackBar(const SnackBar(
        backgroundColor: AppColors.button,
        content: Text('Шахсий маълумот ўчирилди',
            style: TextStyle(color: AppColors.onPrimary)),
      ));
      onDeleted?.call();
    } on AdminDeleteRecordException catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red, content: Text(_eraseErrorText(e))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    }
  }

  static String _eraseErrorText(AdminDeleteRecordException e) {
    switch (e.reason) {
      case 'CHAT_NOT_ARCHIVED':
        return 'Аввал чатни архивга олинг (янги хабар келган чат қайта очилади)';
      case 'REASON_REQUIRED':
        return 'Сабаб камида 10 белги бўлиши керак';
    }
    if (e.code == 'permission-denied') {
      return 'Бу амални фақат superadmin бажара олади';
    }
    return 'Хатoлик: $e';
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
        // Ўчириш ЙЎҚ: чат архивга олинади (қайтариладиган амал).
        TextButton.icon(
          key: ValueKey(widget.archived ? 'chat-unarchive' : 'chat-archive'),
          onPressed: () => _setArchived(!widget.archived),
          icon: Icon(
              widget.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              size: 18),
          label: Text(widget.archived ? 'Архивдан чиқариш' : 'Архивга олиш'),
        ),
        // Шахсий маълумотни ўчириш — алоҳида меню, фақат superadmin кўради.
        if (context.watch<AdminAuthService>().isSuperAdmin)
          PopupMenuButton<String>(
            key: const ValueKey('chat-more'),
            tooltip: 'Яна',
            onSelected: (v) {
              if (v == 'erase') _erasePersonalData();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                key: const ValueKey('chat-erase'),
                value: 'erase',
                enabled: widget.archived,
                child: Text(
                  widget.archived
                      ? 'Шахсий маълумотни ўчириш (талаб бўйича)'
                      : 'Шахсий маълумотни ўчириш (аввал архивга олинг)',
                  style: TextStyle(
                      color: widget.archived ? Colors.red : Colors.grey),
                ),
              ),
            ],
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

/// Шахсий маълумотни ўчириш диалоги: сабаб (камида 10 белги) + тасдиқ белгиси. Тасдиқланса — сабаб матнини қайтаради.
class _EraseDialog extends StatefulWidget {
  const _EraseDialog({required this.chatId});
  final String chatId;

  @override
  State<_EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<_EraseDialog> {
  final _reasonCtrl = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _valid => _confirmed && _reasonCtrl.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Шахсий маълумотни ўчириш'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '+${widget.chatId} билан бутун ёзишма ТЎЛИҚ ўчади — мижоз ўз '
              'иловасида ҳам кўрмайди. Қайтариб бўлмайди. Фақат санаш '
              'маълумоти (матнсиз), сабаб ва ким бажаргани audit журналида қолади.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('erase-reason'),
              controller: _reasonCtrl,
              maxLines: 2,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Сабаб (камида 10 белги)',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('erase-confirm'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v == true),
              title: const Text(
                  'Мижоз шахсий маълумотни ўчиришни талаб қилган'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        TextButton(
          key: const ValueKey('erase-submit'),
          onPressed:
              _valid ? () => Navigator.pop(context, _reasonCtrl.text.trim()) : null,
          child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.staffDigits});
  final ChatMessage msg;

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
                    ]),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}
