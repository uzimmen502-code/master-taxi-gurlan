import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/tree_history_entry.dart';
import '../../../repositories/tree_repository.dart';
import '../l10n/relatives_l10n.dart';
import '../services/tree_service.dart';

/// 🕓 Nasab daraxti tarixi — amallar jurnali + Undo (Faza 4).
class TreeHistoryScreen extends StatefulWidget {
  const TreeHistoryScreen({super.key, required this.userId});

  final String userId;

  @override
  State<TreeHistoryScreen> createState() => _TreeHistoryScreenState();
}

class _TreeHistoryScreenState extends State<TreeHistoryScreen> {
  static const _accent = Color(0xFF6A4C93);
  final _repo = TreeRepository();
  final _busy = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('rel_history_title')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<({String componentId, String personId})>(
        stream: _repo.watchMyTreeMeta(widget.userId),
        builder: (context, metaSnap) {
          final componentId = metaSnap.data?.componentId ?? '';
          if (metaSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<TreeHistoryEntry>>(
            stream: _repo.watchHistory(componentId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data ?? const <TreeHistoryEntry>[];
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.tr('rel_history_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _tile(items[i]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _tile(TreeHistoryEntry e) {
    final busy = _busy.contains(e.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(RelativesL10n.historyTypeLabel(context, e.type),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: _accent)),
                      if (e.undone) ...[
                        const SizedBox(width: 8),
                        Text(context.tr('rel_history_undone'),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(e.summary),
                  if (e.createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(_fmt(e.createdAt!),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (e.canUndo)
              busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: () => _undo(e),
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(context.tr('rel_history_undo')),
                    ),
          ],
        ),
      ),
    );
  }

  Future<void> _undo(TreeHistoryEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rel_undo_title')),
        content: Text(RelativesL10n.trParams(
            ctx, 'rel_undo_body', {'summary': e.summary})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('no'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('rel_undo_confirm'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(e.id));
    try {
      await TreeService.undoOperation(e.id);
      _snack(context.tr('rel_undo_done'));
    } on FirebaseFunctionsException catch (ex) {
      _snack(firebaseFunctionsUserMessage(ex));
    } catch (ex) {
      _snack(RelativesL10n.trParams(
          context, 'error_generic', {'error': '$ex'}));
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
