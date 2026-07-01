import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/tree_link_invite.dart';
import '../../../repositories/tree_repository.dart';
import '../services/tree_service.dart';

/// Daraxt ulash takliflari — pastki varaq (qabul / rad).
void showTreeLinkInvitesSheet(BuildContext context, String userId) {
  const accent = Color(0xFF6A4C93);
  final repo = TreeRepository();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: StreamBuilder<List<TreeLinkInvite>>(
        stream: repo.watchIncomingInvites(userId),
        builder: (context, snap) {
          final invites = snap.data ?? const <TreeLinkInvite>[];
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (invites.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Кутилмаётган улаш таклифи йўқ.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Улаш таклифлари',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              for (final inv in invites)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${inv.fromName.isEmpty ? "Фойдаланувчи" : inv.fromName} '
                          'сизни «${inv.nodeName}» сифатида ўз дарахтига улашни '
                          'таклиф қилмоқда.',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _respond(context, inv, false, accent),
                              child: const Text('Рад этиш'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () =>
                                  _respond(context, inv, true, accent),
                              child: const Text('Қабул қилиш'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> _respond(
  BuildContext context,
  TreeLinkInvite inv,
  bool accept,
  Color accent,
) async {
  try {
    final res =
        await TreeService.respondLinkInvite(inviteId: inv.id, accept: accept);
    if (!context.mounted) return;
    final msg = res['status'] == 'accepted'
        ? '🎉 Дарахтлар бирлашди!'
        : 'Таклиф рад этилди.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  } on FirebaseFunctionsException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(firebaseFunctionsUserMessage(e))),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Хатолик: $e')));
  }
}
