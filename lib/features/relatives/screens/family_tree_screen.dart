import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/relative_person.dart';
import '../../../models/tree_link_invite.dart';
import '../../../models/tree_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../../../repositories/tree_repository.dart';
import '../services/tree_redirect_resolver.dart';
import '../services/tree_service.dart';
import '../widgets/tree_link_invites_sheet.dart';
import 'family_tree_view.dart';
import 'tree_node_edit_screen.dart';

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
  final _relRepo = RelativesRepository();

  /// Eng so'nggi komponent tugunlari (tahrirlash dropdownlari uchun).
  List<TreePerson> _comp = const [];
  Map<String, RelativePerson> _personalById = const {};

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
            onTap: () => showTreeLinkInvitesSheet(context, widget.userId),
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
    // Daraxt ikki manba birlashmasidan quriladi:
    //  - shaxsiy relatives/people (foydalanuvchi qo'lda tuzgan bog'lanishlar)
    //  - tree_persons komponenti (ulangan qarindoshlar + "Men" tuguni)
    return StreamBuilder<({String componentId, String personId})>(
      stream: _repo.watchMyTreeMeta(widget.userId),
      builder: (context, metaSnap) {
        final componentId = metaSnap.data?.componentId ?? '';
        return StreamBuilder<List<RelativePerson>>(
          stream: _relRepo.watchPeople(widget.userId),
          builder: (context, personalSnap) {
            return StreamBuilder<Map<String, String>>(
              stream: _repo.watchRedirects(),
              builder: (context, redirSnap) {
                final redirects = redirSnap.data ?? const {};
                return StreamBuilder<List<TreePerson>>(
                  stream: _repo.watchComponent(componentId),
                  builder: (context, compSnap) {
                    final personal =
                        personalSnap.data ?? const <RelativePerson>[];
                    final comp = compSnap.data ?? const <TreePerson>[];
                    _personalById = {for (final p in personal) p.id: p};
                    if (personalSnap.connectionState ==
                            ConnectionState.waiting &&
                        compSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final compById = {for (final n in comp) n.id: n};
                    final renderById = <String, RelativePerson>{};
                    final allIds = {
                      ...comp.map((n) => n.id),
                      ...personal.map((p) => p.id),
                    };
                    for (final id in allIds) {
                      if (redirects.containsKey(id)) continue;
                      final merged = _mergeForTreeDisplay(
                        _personalById[id],
                        compById[id],
                      );
                      renderById[id] =
                          resolvePersonLinks(merged, redirects);
                    }
                    final people =
                        renderById.values.toList(growable: false);
                    final dupGroups = findDuplicateGroups(comp);
                    _comp = comp;

                    return Column(
                      children: [
                        if (dupGroups.isNotEmpty) _dupBar(dupGroups),
                        Expanded(
                          child: FamilyTreeView(
                            people: people,
                            onTap: (RelativePerson p) {
                              final node = compById[p.id];
                              if (node != null) {
                                _onNodeTap(node);
                              } else if (widget.onEditOwnNode != null) {
                                widget.onEditOwnNode!(p.id);
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _mergeGroup(BuildContext sheetCtx, List<TreePerson> group) async {
    Navigator.pop(sheetCtx);
    final keep = group.firstWhere((n) => n.isClaimed, orElse: () => group.first);
    final others = group.where((n) => n.id != keep.id).toList();
    final bothClaimed = others.any((n) => n.isClaimed && n.claimedBy != keep.claimedBy);
    if (bothClaimed) {
      _snack('Иккала тугун ҳам аккаунтга уланган — бирлаштириб бўлмайди.');
      return;
    }
    final label = duplicateGroupLabel(group);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Такрорларни бирлаштириш'),
        content: Text(
          '«$label» — ${group.length} та тугун.\n\n'
          'Бу bir xil odam deb ishonchingiz komilmi?\n'
          '«${keep.fullName}» saqlanadi, qolganlari o‘chiriladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Бирлаштириш'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var done = 0;
    try {
      for (final m in others) {
        await TreeService.mergeTreePersons(keepId: keep.id, mergeId: m.id);
        done++;
      }
      _snack('$done та тугун «${keep.fullName}» билан бирлаштирилди.');
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack('Хатолик ($done bajarildi): $e');
    }
  }

  /// Daraxt ko'rinishi: nasab (ism, bog'lanish) komponentdan; shaxsiy faqat aloqa.
  RelativePerson _mergeForTreeDisplay(
    RelativePerson? personal,
    TreePerson? comp,
  ) {
    if (comp == null) return personal!;
    if (personal == null) return comp.toRelativePerson();
    return RelativePerson(
      id: comp.id,
      fullName: comp.fullName.isNotEmpty ? comp.fullName : personal.fullName,
      photoUrl:
          comp.photoUrl.isNotEmpty ? comp.photoUrl : personal.photoUrl,
      photoPath: personal.photoPath,
      phone: personal.phone,
      address: personal.address,
      birthDate: comp.birthDate ?? personal.birthDate,
      gender: comp.gender.isNotEmpty ? comp.gender : personal.gender,
      relationDegree: personal.relationDegree,
      side: personal.side,
      notes: personal.notes,
      fatherId: comp.fatherId ?? personal.fatherId,
      motherId: comp.motherId ?? personal.motherId,
      spouseId: comp.spouseId ?? personal.spouseId,
      isSelf: personal.isSelf,
      createdAt: personal.createdAt,
    );
  }

  Widget _dupBar(List<List<TreePerson>> groups) {
    final count = groups.fold<int>(0, (a, g) => a + g.length);
    return Material(
      color: const Color(0xFFFFF3E0),
      child: InkWell(
        onTap: () => _openDedup(groups),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.merge_type, color: Color(0xFFE67E22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count та эҳтимолий такрор топилди — бирлаштириш учун босинг',
                  style: const TextStyle(
                      color: Color(0xFFB9650F), fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFE67E22)),
            ],
          ),
        ),
      ),
    );
  }

  void _openDedup(List<List<TreePerson>> groups) {
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
              child: Text('Эҳтимолий такрорлар',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Исм, туғилган сана ва жинс mos kelsa — bir xil odam bo‘lishi mumkin.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            for (final g in groups)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${duplicateGroupLabel(g)} — ${g.length} та',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      for (final n in g)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline, size: 18),
                              const SizedBox(width: 6),
                              Expanded(child: Text(n.fullName)),
                              if (n.isClaimed)
                                const Text('✓ уланган',
                                    style: TextStyle(
                                        color: Colors.green, fontSize: 12)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE67E22),
                              foregroundColor: Colors.white),
                          onPressed: () => _mergeGroup(ctx, g),
                          icon: const Icon(Icons.merge_type, size: 18),
                          label: const Text('Бирлаштириш'),
                        ),
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
            ListTile(
              leading: const Icon(Icons.account_tree_outlined, color: _accent),
              title: const Text('Таҳрирлаш (умумий тармоқ)'),
              subtitle: const Text('Исм, сана, ота/она/турмуш ўртоғи'),
              onTap: () {
                Navigator.pop(ctx);
                _editNode(node);
              },
            ),
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
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Шахсий маълумотлар'),
                subtitle: const Text('Телефон, манзил, изоҳ, фотоальбом'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onEditOwnNode!(node.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _editNode(TreePerson node) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TreeNodeEditScreen(
          userId: widget.userId,
          componentNodes: _comp,
          existing: node,
        ),
      ),
    );
  }

  String _invitePhoneInitial(TreePerson node) {
    final listed = _personalById[node.id]?.phone.trim() ?? '';
    if (listed.isNotEmpty) return phoneForCall(listed);
    return '+998';
  }

  Future<void> _sendInvite(TreePerson node) async {
    final ctrl = TextEditingController(text: _invitePhoneInitial(node));
    String? phone;
    try {
      phone = await showDialog<String>(
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
    } finally {
      ctrl.dispose();
    }
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
