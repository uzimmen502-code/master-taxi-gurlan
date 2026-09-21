import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/assistant_conversation.dart';
import '../services/assistant_service.dart';
import 'assistant_gpt_colors.dart';

/// ChatGPT'нинг чап панели: «Янги суҳбат», суҳбатлар (Бугун / Кеча /
/// Олдинги 7 кун / Олдинги 30 кун / ойлар бўйича), узоқ босиш — қайта
/// номлаш/ўчириш; пастда «Хотира».
class AssistantDrawer extends StatelessWidget {
  const AssistantDrawer({
    super.key,
    required this.uid,
    required this.service,
    required this.activeId,
    required this.onNewChat,
    required this.onOpen,
    required this.onOpenMemory,
  });

  final String uid;
  final AssistantService service;
  final String? activeId;
  final VoidCallback onNewChat;
  final ValueChanged<AssistantConversation> onOpen;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Drawer(
      backgroundColor: c.drawerBg,
      width: MediaQuery.sizeOf(context).width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: _DrawerButton(
                icon: Icons.edit_square,
                label: context.tr('assistant_new_chat'),
                onTap: onNewChat,
                bold: true,
              ),
            ),
            Expanded(
              child: StreamBuilder<List<AssistantConversation>>(
                stream: service.watchConversations(uid),
                builder: (context, snap) {
                  final list = snap.data ?? const <AssistantConversation>[];
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        context.tr('assistant_no_chats'),
                        style: GoogleFonts.inter(fontSize: 13, color: c.subtle),
                      ),
                    );
                  }
                  final groups = _groupByDate(context, list);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    children: [
                      for (final g in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                          child: Text(
                            g.label,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.subtle,
                            ),
                          ),
                        ),
                        for (final conv in g.items)
                          _ConversationTile(
                            conv: conv,
                            active: conv.id == activeId,
                            onTap: () => onOpen(conv),
                            onLongPress: () => _showActions(context, conv),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: _DrawerButton(
                icon: Icons.psychology_outlined,
                label: context.tr('assistant_memory'),
                onTap: onOpenMemory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    AssistantConversation conv,
  ) async {
    final c = GptColors.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                conv.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline, color: c.text),
              title: Text(ctx.tr('assistant_rename'),
                  style: GoogleFonts.inter(color: c.text)),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
              title: Text(ctx.tr('assistant_delete'),
                  style: GoogleFonts.inter(color: const Color(0xFFE53935))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    if (action == 'rename') {
      final ctrl = TextEditingController(text: conv.title);
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('assistant_rename')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ctx.tr('save')),
            ),
          ],
        ),
      );
      if (title != null && title.isNotEmpty && title != conv.title) {
        try {
          await service.renameConversation(conv.id, title);
        } catch (_) {
          if (context.mounted) _snack(context, context.tr('assistant_err_unavailable'));
        }
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('assistant_delete')),
          content: Text(ctx.tr('assistant_delete_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('assistant_delete')),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await service.deleteConversation(conv.id);
          if (context.mounted && conv.id == activeId) onNewChat();
        } catch (_) {
          if (context.mounted) _snack(context, context.tr('assistant_err_unavailable'));
        }
      }
    }
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<_Group> _groupByDate(
    BuildContext context,
    List<AssistantConversation> list,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <String, List<AssistantConversation>>{};
    final order = <String>[];
    for (final conv in list) {
      final d = conv.updatedAt;
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      final String label;
      if (diff <= 0) {
        label = context.tr('assistant_group_today');
      } else if (diff == 1) {
        label = context.tr('assistant_group_yesterday');
      } else if (diff < 7) {
        label = context.tr('assistant_group_week');
      } else if (diff < 30) {
        label = context.tr('assistant_group_month');
      } else {
        label = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      }
      if (!groups.containsKey(label)) {
        groups[label] = [];
        order.add(label);
      }
      groups[label]!.add(conv);
    }
    return [for (final l in order) _Group(l, groups[l]!)];
  }
}

class _Group {
  const _Group(this.label, this.items);
  final String label;
  final List<AssistantConversation> items;
}

class _DrawerButton extends StatelessWidget {
  const _DrawerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.text),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                  color: c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conv,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  final AssistantConversation conv;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Material(
      color: active ? c.bubble : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Text(
            conv.title.isEmpty ? context.tr('assistant_new_chat') : conv.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 14.5, color: c.text),
          ),
        ),
      ),
    );
  }
}
