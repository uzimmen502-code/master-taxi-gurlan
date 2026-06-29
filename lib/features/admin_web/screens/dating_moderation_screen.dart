import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../models/dating_profile.dart';
import '../../../repositories/dating_repository.dart';
import '../../dating/services/dating_service.dart';

/// Admin: tanishuv profillari moderatsiyasi + shikoyatlar.
class DatingModerationScreen extends StatelessWidget {
  const DatingModerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4F8),
        appBar: AppBar(
          title: const Text('❤️ Танишув модерацияси'),
          backgroundColor: const Color(0xFFE5446D),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Текширувда'),
              Tab(text: 'Шикоятлар'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingProfilesTab(),
            _ReportsTab(),
          ],
        ),
      ),
    );
  }
}

class _PendingProfilesTab extends StatelessWidget {
  const _PendingProfilesTab();

  @override
  Widget build(BuildContext context) {
    final repo = DatingRepository();
    return StreamBuilder<List<DatingProfile>>(
      stream: repo.watchByStatus('pending'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const <DatingProfile>[];
        if (list.isEmpty) {
          return const Center(child: Text('Текширувда профил йўқ.'));
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
            const SizedBox(height: 12),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _moderate('approve'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.check),
                      label: const Text('Тасдиқлаш'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _moderate('reject'),
                    child: const Text('Рад'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _moderate('block'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Text('Блок'),
                  ),
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
                    onPressed: () async {
                      try {
                        await DatingService.adminModerate(
                            userId: targetId,
                            action: 'block',
                            reason: 'Шикоят асосида');
                      } catch (_) {}
                      await docs[i].reference.update({'status': 'resolved'});
                    },
                  ),
                  IconButton(
                    tooltip: 'Ҳал қилинди',
                    icon: const Icon(Icons.done, color: Colors.green),
                    onPressed: () =>
                        docs[i].reference.update({'status': 'resolved'}),
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
