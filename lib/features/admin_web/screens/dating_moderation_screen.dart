import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/dating_profile.dart';
import '../../../repositories/dating_repository.dart';
import '../../dating/services/dating_service.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_dating_service.dart';
import '../services/admin_moderation_modes_service.dart';
import '../widgets/moderation_mode_bar.dart';

/// Admin: tanishuv profillari moderatsiyasi + shikoyatlar.
class DatingModerationScreen extends StatelessWidget {
  const DatingModerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Аввал фақат `pending` кўринарди: блокланган/рад этилган профилни
    // админ топа олмасди — блокдан чиқариш ёки тасдиқни қайтариб олиш
    // мумкин эмас эди (CF ҳар қандай ҳолатдан рухсат беради; аудит O-14).
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4F8),
        appBar: AppBar(
          title: const Text('❤️ Танишув модерацияси'),
          backgroundColor: const Color(0xFFE5446D),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Текширувда'),
              Tab(text: 'Шикоятлар'),
              Tab(text: 'Блокланган'),
              Tab(text: 'Рад этилган'),
              Tab(text: 'Тасдиқланган'),
            ],
          ),
        ),
        body: const Column(
          children: [
            ModerationModeBar(
              mode: ModerationMode.dating,
              onLabel: 'Автоматик тасдиқлаш: ЁҚИҚ — янги профиллар дарҳол тасдиқланади',
              offLabel: 'Қўлда тасдиқлаш — янги профиллар «Текширувда»га тушади',
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ProfilesByStatusTab('pending', 'Текширувда профил йўқ.'),
                  _ReportsTab(),
                  _ProfilesByStatusTab('blocked', 'Блокланган профил йўқ.'),
                  _ProfilesByStatusTab('rejected', 'Рад этилган профил йўқ.'),
                  _ProfilesByStatusTab('approved', 'Тасдиқланган профил йўқ.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilesByStatusTab extends StatefulWidget {
  const _ProfilesByStatusTab(this.status, this.emptyText);

  final String status;
  final String emptyText;

  @override
  State<_ProfilesByStatusTab> createState() => _ProfilesByStatusTabState();
}

class _ProfilesByStatusTabState extends State<_ProfilesByStatusTab> {
  late final Stream<List<DatingProfile>> _stream =
      DatingRepository().watchByStatus(widget.status);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatingProfile>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const <DatingProfile>[];
        if (list.isEmpty) {
          return Center(child: Text(widget.emptyText));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) => _ProfileModerationCard(profile: list[i]),
        );
      },
    );
  }
}

class _ProfileModerationCard extends StatefulWidget {
  const _ProfileModerationCard({required this.profile});
  final DatingProfile profile;

  @override
  State<_ProfileModerationCard> createState() => _ProfileModerationCardState();
}

class _ProfileModerationCardState extends State<_ProfileModerationCard> {
  bool _busy = false;

  Future<void> _moderate(String action) async {
    String reason = '';
    if (action != 'approve') {
      final ctrl = TextEditingController();
      final r = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'reject' ? 'Рад этиш сабаби' : 'Блоклаш сабаби'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                hintText: 'Сабаб (масалан: сохта расм)',
                border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Бекор')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Тасдиқ')),
          ],
        ),
      );
      if (r == null) return;
      reason = r;
    }
    setState(() => _busy = true);
    try {
      await DatingService.adminModerate(
        userId: widget.profile.userId,
        action: action,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Бажарилди.')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Хатолик: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.photos.isNotEmpty)
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(p.photos[i].url,
                        width: 130, height: 160, fit: BoxFit.cover),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '${p.displayName}${p.age != null ? ', ${p.age}' : ''} · '
              '${p.gender == 'male' ? '👨' : '👩'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text('ID: ${p.userId}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (p.city.isNotEmpty) Chip(label: Text('📍 ${p.city}')),
              if (p.maritalStatus.isNotEmpty) Chip(label: Text(p.maritalStatus)),
              if (p.education.isNotEmpty) Chip(label: Text('🎓 ${p.education}')),
              if (p.job.isNotEmpty) Chip(label: Text('💼 ${p.job}')),
            ]),
            if (p.about.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.about),
            ],
            if (p.status != 'pending' && p.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Сабаб: ${p.rejectionReason}',
                  style: TextStyle(color: Colors.red.shade700)),
            ],
            const SizedBox(height: 12),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              // Ҳозирги ҳолатга ўтиш тугмаси кўрсатилмайди.
              Row(
                children: [
                  if (p.status != 'approved')
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _moderate('approve'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AvaLight.ok,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.check),
                        label: Text(p.status == 'blocked'
                            ? 'Блокдан чиқариш'
                            : 'Тасдиқлаш'),
                      ),
                    )
                  else
                    const Spacer(),
                  if (p.status != 'rejected') ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _moderate('reject'),
                      child: Text(p.status == 'approved'
                          ? 'Тасдиқни қайтариш'
                          : 'Рад'),
                    ),
                  ],
                  if (p.status != 'blocked') ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _moderate('block'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      child: const Text('Блок'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  String _adminPhone(BuildContext context) {
    final auth = context.read<AdminAuthService>();
    if (auth.phoneDigits != null && auth.phoneDigits!.isNotEmpty) {
      return auth.phoneDigits!;
    }
    final d = phoneDigits(auth.phone ?? '');
    return d.length >= 9 ? d : '';
  }

  Future<void> _resolveReport(
    BuildContext context,
    String reportId, {
    String? blockUserId,
  }) async {
    final adminPhone = _adminPhone(context);
    if (adminPhone.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    // Блоклаш муваффақиятсиз бўлса — шикоят ЁПИЛМАЙДИ: аввал хато
    // ютилиб (`catch (_) {}`), шикоят «ҳал қилинди» бўлиб кетарди, профил
    // эса очиқ қоларди. Ҳал қилиш хатоси ҳам кўрсатилади.
    try {
      if (blockUserId != null && blockUserId.isNotEmpty) {
        await DatingService.adminModerate(
          userId: blockUserId,
          action: 'block',
          reason: 'Шикоят асосида',
        );
      }
      await AdminDatingService.resolveReport(
        adminPhone: adminPhone,
        reportId: reportId,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Бажарилмади: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('reports')
        .where('type', isEqualTo: 'dating_profile')
        .where('status', isEqualTo: 'open')
        .limit(200);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('Очиқ шикоят йўқ.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final targetId = (d['targetId'] ?? '') as String;
            return ListTile(
              leading: const Icon(Icons.flag, color: Colors.red),
              title: Text('Профил: $targetId'),
              subtitle: Text(
                  'Сабаб: ${d['reason'] ?? ''}\nЮборувчи: ${d['reporterId'] ?? ''}'),
              isThreeLine: true,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Профилни блоклаш',
                    icon: const Icon(Icons.block, color: Colors.red),
                    onPressed: () => _resolveReport(
                      context,
                      docs[i].id,
                      blockUserId: targetId,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ҳал қилинди',
                    icon: const Icon(Icons.done, color: AvaLight.ok),
                    onPressed: () =>
                        _resolveReport(context, docs[i].id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
