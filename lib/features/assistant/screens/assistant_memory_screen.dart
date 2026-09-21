import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/assistant_conversation.dart';
import '../services/assistant_service.dart';
import '../widgets/assistant_gpt_colors.dart';

/// «Хотира» — ChatGPT'нинг Manage memory экрани: ёрдамчи аввалги
/// суҳбатлардан эслаб қолган фактлар; ҳар бирини ёки ҳаммасини ўчириш.
class AssistantMemoryScreen extends StatelessWidget {
  const AssistantMemoryScreen({
    super.key,
    required this.uid,
    required this.service,
  });

  final String uid;
  final AssistantService service;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        title: Text(
          context.tr('assistant_memory'),
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _clearAll(context),
            child: Text(
              context.tr('assistant_memory_clear'),
              style: GoogleFonts.inter(color: const Color(0xFFE53935)),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<AssistantMemoryItem>>(
        stream: service.watchMemory(uid),
        builder: (context, snap) {
          final list = snap.data ?? const <AssistantMemoryItem>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                context.tr('assistant_memory_hint'),
                style: GoogleFonts.inter(fontSize: 13.5, color: c.subtle, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      context.tr('assistant_memory_empty'),
                      style: GoogleFonts.inter(color: c.subtle),
                    ),
                  ),
                ),
              for (final m in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: c.bubble,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.text,
                          style: GoogleFonts.inter(fontSize: 15, color: c.text, height: 1.4),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: c.subtle),
                        tooltip: context.tr('assistant_delete'),
                        onPressed: () => _delete(context, m.id),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, String id) async {
    try {
      await service.deleteMemory(id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('assistant_err_unavailable'))),
        );
      }
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_memory_clear')),
        content: Text(ctx.tr('assistant_memory_clear_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('assistant_delete')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await _delete(context, '*');
  }
}
