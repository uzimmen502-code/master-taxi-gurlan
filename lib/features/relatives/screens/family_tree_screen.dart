import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/relative_person.dart';
import '../../../models/tree_link_invite.dart';
import '../../../models/tree_person.dart';
import '../../../repositories/tree_repository.dart';
import '../l10n/relatives_l10n.dart';
import '../services/family_tree_bundle.dart';
import '../services/tree_export_handle.dart';
import '../services/tree_export_service.dart';
import '../services/tree_redirect_resolver.dart';
import '../services/tree_service.dart';
import '../widgets/tree_link_invites_sheet.dart';
import 'family_tree_view.dart';
import 'tree_node_edit_screen.dart';

/// 🌳 Nasab daraxti — global komponentdan o'qiydi (ulangan oila tarmog'i).
class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({
    super.key,
    required this.userId,
    this.onEditOwnNode,
    this.exportHandle,
  });

  final String userId;
  final void Function(String nodeId)? onEditOwnNode;
  final TreeExportHandle? exportHandle;

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  static const _accent = Color(0xFF6A4C93);
  final _repo = TreeRepository();

  List<TreePerson> _comp = const [];
  Map<String, RelativePerson> _personalById = const {};
  List<RelativePerson> _exportPeople = const [];
  final _treeCaptureKey = GlobalKey();
  bool _exportBusy = false;
  late final Stream<FamilyTreeBundle> _bundleStream =
      FamilyTreeBundleSource(userId: widget.userId).watch();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _invitesBanner(),
        Expanded(child: _tree()),
      ],
    );
  }

  void _syncExportHandle() {
    widget.exportHandle?.bind(
      canExport: !_exportBusy && _exportPeople.isNotEmpty,
      busy: _exportBusy,
      gedcom: _exportGedcom,
      png: _exportPng,
      pdf: _exportPdf,
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
                      RelativesL10n.trParams(context, 'rel_invite_banner', {
                        'count': '${invites.length}',
                      }),
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
    return StreamBuilder<FamilyTreeBundle>(
      stream: _bundleStream,
      builder: (context, snap) {
        if (snap.hasError) return _streamError(snap.error);
        final bundle = snap.data;
        if (bundle == null || bundle.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final people = bundle.renderPeople;
        final dupGroups = bundle.duplicateGroups;
        final compById = bundle.componentById;
        _personalById = bundle.personalById;
        _comp = bundle.component;
        _exportPeople = people;
        _syncExportHandle();

        return Column(
          children: [
            if (dupGroups.isNotEmpty) _dupBar(dupGroups),
            Expanded(
              child: FamilyTreeView(
                exportCaptureKey: _treeCaptureKey,
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
  }

  Future<void> _mergeGroup(
      BuildContext sheetCtx, List<TreePerson> group) async {
    Navigator.pop(sheetCtx);
    final keep =
        group.firstWhere((n) => n.isClaimed, orElse: () => group.first);
    final others = group.where((n) => n.id != keep.id).toList();
    final bothClaimed = others
        .any((n) => n.isClaimed && n.claimedBy != keep.claimedBy);
    if (bothClaimed) {
      await _showBothClaimedDialog();
      return;
    }
    final label = duplicateGroupLabel(group);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rel_tree_merge_title')),
        content: Text(RelativesL10n.trParams(ctx, 'rel_tree_merge_body', {
          'label': label,
          'count': '${group.length}',
          'keep': keep.fullName,
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('no')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('rel_tree_dup_merge')),
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
      _snack(RelativesL10n.trParams(context, 'rel_tree_merge_success', {
        'count': '$done',
        'name': keep.fullName,
      }));
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack(RelativesL10n.trParams(context, 'rel_tree_merge_partial_error', {
        'done': '$done',
        'error': '$e',
      }));
    }
  }

  Future<void> _showBothClaimedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rel_tree_merge_both_claimed_title')),
        content: Text(ctx.tr('rel_tree_merge_both_claimed_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('ok')),
          ),
        ],
      ),
    );
  }

  bool _groupHasBothClaimed(List<TreePerson> group) {
    final claimedBys = group
        .where((n) => n.isClaimed)
        .map((n) => n.claimedBy)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    return claimedBys.length > 1;
  }

  Widget _dupGroupAction(BuildContext sheetCtx, List<TreePerson> group) {
    if (_groupHasBothClaimed(group)) {
      return TextButton.icon(
        onPressed: () {
          Navigator.pop(sheetCtx);
          unawaited(_showBothClaimedDialog());
        },
        icon: const Icon(Icons.info_outline, size: 18),
        label: Text(sheetCtx.tr('rel_tree_merge_both_claimed_why')),
      );
    }
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE67E22),
        foregroundColor: Colors.white,
      ),
      onPressed: () => _mergeGroup(sheetCtx, group),
      icon: const Icon(Icons.merge_type, size: 18),
      label: Text(sheetCtx.tr('rel_tree_dup_merge')),
    );
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    _syncExportHandle();
    try {
      await action();
      if (mounted) _snack(context.tr('rel_tree_export_share_opened'));
    } on StateError catch (e) {
      if (e.message == 'empty') {
        _snack(context.tr('rel_tree_export_empty'));
      } else {
        _snack(context.tr('rel_tree_export_capture_fail'));
      }
    } catch (e) {
      _snack(RelativesL10n.trParams(
          context, 'error_generic', {'error': '$e'}));
    } finally {
      if (mounted) {
        setState(() => _exportBusy = false);
        _syncExportHandle();
      }
    }
  }

  Future<void> _exportGedcom() =>
      _runExport(() => TreeExportService.shareGedcom(_exportPeople));

  Future<void> _exportPng() =>
      _runExport(() => TreeExportService.shareTreePng(_treeCaptureKey));

  Future<void> _exportPdf() =>
      _runExport(() => TreeExportService.shareTreePdf(_treeCaptureKey));

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
                  RelativesL10n.trParams(context, 'rel_tree_dup_banner', {
                    'count': '$count',
                  }),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(ctx.tr('rel_tree_dup_title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                ctx.tr('rel_tree_dup_hint'),
                style: const TextStyle(color: Colors.grey),
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
                      Text(
                          RelativesL10n.trParams(ctx, 'rel_tree_dup_group', {
                            'label': duplicateGroupLabel(g),
                            'count': '${g.length}',
                          }),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                Text(ctx.tr('rel_tree_dup_linked'),
                                    style: const TextStyle(
                                        color: Colors.green, fontSize: 12)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _dupGroupAction(ctx, g),
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
                  ? Text(ctx.tr('rel_node_claimed'))
                  : (isMine ? Text(ctx.tr('rel_node_yours')) : null),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _accent),
              title: Text(ctx.tr('edit')),
              subtitle: Text(
                isMine
                    ? ctx.tr('rel_node_edit_unified_sub')
                    : ctx.tr('rel_node_edit_sub'),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (isMine && widget.onEditOwnNode != null) {
                  widget.onEditOwnNode!(node.id);
                } else {
                  _editNode(node);
                }
              },
            ),
            if (isMine && !isSelf && !node.isClaimed)
              ListTile(
                leading: const Icon(Icons.link, color: _accent),
                title: Text(ctx.tr('rel_node_link_account')),
                subtitle: Text(ctx.tr('rel_node_link_sub')),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendInvite(node);
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
          title: Text(RelativesL10n.trParams(
              ctx, 'rel_link_dialog_title', {'name': node.fullName})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ctx.tr('rel_link_dialog_body')),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: ctx.tr('phone'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.tr('cancel'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ctx.tr('rel_send')),
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
          ? context.tr('rel_link_already_sent')
          : context.tr('rel_link_sent'));
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack(RelativesL10n.trParams(
          context, 'error_generic', {'error': '$e'}));
    }
  }

  Widget _streamError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              context.tr('rel_tree_load_error'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
