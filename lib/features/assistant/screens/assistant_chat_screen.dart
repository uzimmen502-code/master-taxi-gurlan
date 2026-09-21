import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../profile/screens/wallet_screen.dart';
import '../models/assistant_message.dart';
import '../models/assistant_status.dart';
import '../services/assistant_service.dart';
import '../widgets/assistant_pro_sheet.dart';

/// «AVA ёрдамчиси» — илова ичидаги AI чат (В-1).
///
/// Тарих `users/{uid}/assistant_messages` stream'идан; юбориш —
/// `assistantChat` callable. Лимит/Pro ҳолати серверда ([AssistantStatus]).
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key, required this.phone});

  final String phone;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _service = AssistantService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  AssistantStatus? _status;
  bool _sending = false;
  AssistantMessage? _pendingUser;

  String get _uid => phoneDigits(widget.phone);

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await _service.getStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // Статус — фақат кўрсатиш учун; юбориш барибир серверда текширилади.
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    final s = _status;
    if (s != null && !s.pro && s.remainingToday <= 0) {
      await _openProSheet(limitReached: true);
      return;
    }

    _inputCtrl.clear();
    setState(() {
      _sending = true;
      _pendingUser = AssistantMessage.localUser(text);
    });
    _scrollToEnd();

    try {
      final reply = await _service.send(text);
      if (!mounted) return;
      setState(() => _status = reply.status);
      _scrollToEnd();
    } on AssistantException catch (e) {
      if (!mounted) return;
      _inputCtrl.text = text;
      if (e.isDailyLimit) {
        await _refreshStatus();
        await _openProSheet(limitReached: true);
      } else {
        _snack(_errorText(e));
      }
    } catch (_) {
      if (!mounted) return;
      _inputCtrl.text = text;
      _snack(context.tr('assistant_err_unavailable'));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingUser = null;
        });
      }
    }
  }

  String _errorText(AssistantException e) {
    switch (e.code) {
      case 'too_fast':
        return context.tr('assistant_err_too_fast');
      case 'assistant_disabled':
        return context.tr('assistant_err_disabled');
      case 'text_too_long':
        return context.tr('assistant_err_too_long');
      default:
        return context.tr('assistant_err_unavailable');
    }
  }

  Future<void> _openProSheet({bool limitReached = false}) async {
    AssistantStatus? status = _status;
    if (status == null) {
      try {
        status = await _service.getStatus();
      } catch (_) {
        if (!mounted) return;
        _snack(context.tr('assistant_err_unavailable'));
        return;
      }
    }
    if (!mounted) return;
    final sheetStatus = status;
    final result = await showModalBottomSheet<AssistantPurchaseResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssistantProSheet(
        status: sheetStatus,
        service: _service,
        limitReached: limitReached,
        onTopUp: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WalletScreen(phone: widget.phone)),
        ),
      ),
    );
    if (result != null && mounted) {
      _snack(context.trMsg('assistant_purchased',
          params: {'date': formatDateShort(result.paidUntil)}));
      await _refreshStatus();
    }
  }

  Future<void> _newChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_new_chat')),
        content: Text(ctx.tr('assistant_new_chat_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('yes')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.clearHistory();
    } catch (_) {
      if (!mounted) return;
      _snack(context.tr('assistant_err_unavailable'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 20),
            const SizedBox(width: 8),
            Text(context.tr('assistant_title')),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: context.tr('assistant_new_chat'),
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(status: _status, onPro: () => _openProSheet()),
          Expanded(
            child: StreamBuilder<List<AssistantMessage>>(
              stream: _service.watchMessages(_uid),
              builder: (context, snap) {
                final list = <AssistantMessage>[...?snap.data];
                if (_pendingUser != null) list.add(_pendingUser!);
                if (snap.connectionState == ConnectionState.waiting &&
                    list.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (list.isEmpty && !_sending) {
                  return _EmptyState(
                    onTap: (q) {
                      _inputCtrl.text = q;
                      _send();
                    },
                  );
                }
                if (snap.hasData) _scrollToEnd();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: list.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= list.length) return const _TypingBubble();
                    return _Bubble(message: list[i]);
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: context.tr('assistant_hint'),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    width: 46,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
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

/// Юқоридаги тариф чизиғи: бепул қолдиқ ёки Pro муддати + «Pro» тугмаси.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.onPro});

  final AssistantStatus? status;
  final VoidCallback onPro;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox(height: 4);
    final text = s.pro
        ? context.trMsg('assistant_pro_until',
            params: {'date': formatDateShort(s.paidUntil)})
        : context.trMsg('assistant_free_left',
            params: {'count': '${s.remainingToday}'});
    return Material(
      color: s.pro ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
      child: InkWell(
        onTap: onPro,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                s.pro ? Icons.verified_rounded : Icons.info_outline_rounded,
                size: 18,
                color: s.pro ? const Color(0xFF2E7D32) : const Color(0xFF8D6E00),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!s.pro)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.tr('assistant_pro_button'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final starters = [
      context.tr('assistant_starter_1'),
      context.tr('assistant_starter_2'),
      context.tr('assistant_starter_3'),
      context.tr('assistant_starter_4'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
      children: [
        const Icon(Icons.auto_awesome_rounded,
            size: 48, color: Color(0xFF10A37F)),
        const SizedBox(height: 12),
        Text(
          context.tr('assistant_empty_title'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('assistant_empty_body'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        for (final q in starters)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => onTap(q),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(q, style: const TextStyle(color: Colors.black87)),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isUser;
    final bg = mine ? AppColors.primaryDark : Colors.white;
    final fg = mine ? Colors.white : Colors.black87;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              message.text,
              style: TextStyle(color: fg, fontSize: 15, height: 1.35),
            ),
            if (!mine && message.webSearches > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.public, size: 13, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('assistant_web_search_used'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              context.tr('assistant_thinking'),
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
