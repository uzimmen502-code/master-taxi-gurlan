import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/tree_link_invite.dart';
import '../../../repositories/tree_repository.dart';
import '../l10n/relatives_l10n.dart';
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
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('rel_invite_empty'),
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr('rel_invite_sheet_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  context.tr('rel_invite_privacy_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
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
                          RelativesL10n.trParams(context, 'rel_invite_body', {
                            'from': inv.fromName.isEmpty
                                ? context.tr('rel_invite_from_default')
                                : inv.fromName,
                            'node': inv.nodeName,
                          }),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _respond(context, inv, false, accent),
                              child: Text(context.tr('rel_invite_reject')),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () =>
                                  _respond(context, inv, true, accent),
                              child: Text(context.tr('rel_invite_accept')),
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
  if (accept) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rel_invite_privacy_title')),
        content: Text(ctx.tr('rel_invite_privacy_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('no')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('rel_invite_privacy_confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  try {
    final res =
        await TreeService.respondLinkInvite(inviteId: inv.id, accept: accept);
    if (!context.mounted) return;
    final msg = res['status'] == 'accepted'
        ? context.tr('rel_invite_merged')
        : context.tr('rel_invite_rejected');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  } on FirebaseFunctionsException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(firebaseFunctionsUserMessage(e))),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            RelativesL10n.trParams(context, 'error_generic', {'error': '$e'})),
      ),
    );
  }
}
