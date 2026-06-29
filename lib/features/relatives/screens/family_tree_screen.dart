import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/relative_person.dart';
import '../../../models/tree_link_invite.dart';
import '../../../models/tree_person.dart';
import '../../../repositories/tree_repository.dart';
import '../services/tree_service.dart';
import 'family_tree_view.dart';

/// 🌳 Nasab daraxti — global komponentdan o'qiydi (ulangan oila tarmog'i),
/// tugunni telefon orqali ulash + kelgan takliflar.
class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({
    super.key,
    required this.userId,
    this.onEditOwnNode,
  });

  final String userId;

  /// O'z qarindoshini tahrirlash (relatives/people) — egasi bo'lsa.
  final void Function(String nodeId)? onEditOwnNode;

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  static const _accent = Color(0xFF6A4C93);
  final _repo = TreeRepository();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _invitesBanner(),
        Expanded(child: _tree()),
      ],
    );
  }

  Widget _invitesBanner() {
    return StreamBuilder<List<TreeLinkInvite>>(
      stream: _repo.watchIncomingInvites(widget.userId),
      builder: (context, snap) {
        final invites = snap.data ?? const <TreeLinkInvite>[];
        if (invites.isEmpty) return const SizedBox.shrink();
        return Material(
          color: _accent.withValues(alpha: 0.10),
          child: InkWell(
            onTap: () => _openInvites(invites),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.link, color: _accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${invites.length} та улаш таклифи бор — кўриш учун босинг',
                      style: const TextStyle(
                          color: _accent, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _accent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tree() {
    return StreamBuilder<({String componentId, String personId})>(
      stream: _repo.watchMyTreeMeta(widget.userId),
      builder: (context, metaSnap) {
        final componentId = metaSnap.data?.componentId ?? '';
        if (metaSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<List<TreePerson>>(
          stream: _repo.watchComponent(componentId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final nodes = snap.data ?? const <TreePerson>[];
            final byId = {for (final n in nodes) n.id: n};
            final people = nodes
                .map((n) => n.toRelativePerson())
                .toList(growable: false);
            return FamilyTreeView(
              people: people,
              onTap: (RelativePerson p) {
                final node = byId[p.id];
                if (node != null) _onNodeTap(node);
              },
            );
          },
        );
      },
    );
  }

  void _onNodeTap(TreePerson node) {
    final isMine = node.ownerUid == widget.userId;
    final isSelf = node.claimedBy == widget.userId;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.15),
                backgroundImage: node.photoUrl.isNotEmpty
                    ? NetworkImage(node.photoUrl)
                    : null,
                child: node.photoUrl.isEmpty
                    ? const Icon(Icons.person, color: _accent)
                    : null,
              ),
              title: Text(node.fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: node.isClaimed
                  ? const Text('✓ Аккаунтга уланган')
                  : (isMine ? const Text('Сизнинг рўйхатингиз') : null),
            ),
            const Divider(height: 1),
            if (isMine && !isSelf && !node.isClaimed)
              ListTile(
                leading: const Icon(Icons.link, color: _accent),
                title: const Text('Аккаунтга улаш (телефон орқали)'),
                subtitle: const Text('У қабул қилса, дарахтлар бирлашади'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendInvite(node);
                },
              ),
            if (isMine && widget.onEditOwnNode != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Таҳрирлаш'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onEditOwnNode!(node.id);
                },
              ),
            if (!isMine && !node.isClaimed)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Бу тугун бошқа аъзоники — кўриш учун.',
                    style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendInvite(TreePerson node) async {
    final ctrl = TextEditingController(text: '+998');
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('«${node.fullName}» ни улаш'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Қариндошингизнинг иловадаги телефон рақамини киритинг. '
                'У қабул қилса, дарахтларингиз бирлашади.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Юбориш'),
          ),
        ],
      ),
    );
    if (phone == null || phone.isEmpty) return;
    try {
      final res =
          await TreeService.sendLinkInvite(nodeId: node.id, toPhone: phone);
      if (!mounted) return;
      _snack(res['alreadySent'] == true
          ? 'Таклиф аввал юборилган.'
          : 'Таклиф юборилди.');
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack('Хатолик: $e');
    }
  }

  void _openInvites(List<TreeLinkInvite> invites) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Улаш таклифлари',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                            onPressed: () => _respond(ctx, inv, false),
                            child: const Text('Рад этиш'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white),
                            onPressed: () => _respond(ctx, inv, true),
                            child: const Text('Қабул қилиш'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(
      BuildContext sheetCtx, TreeLinkInvite inv, bool accept) async {
    Navigator.pop(sheetCtx);
    try {
      final res = await TreeService.respondLinkInvite(
          inviteId: inv.id, accept: accept);
      if (!mounted) return;
      if (res['status'] == 'accepted') {
        _snack('🎉 Дарахтлар бирлашди!');
      } else {
        _snack('Таклиф рад этилди.');
      }
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack('Хатолик: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
