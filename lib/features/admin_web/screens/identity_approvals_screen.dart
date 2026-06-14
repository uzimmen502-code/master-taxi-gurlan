import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/identity_change_request.dart';
import '../../../repositories/user_repository.dart';
import '../../../core/theme/app_theme.dart';

class IdentityApprovalsScreen extends StatelessWidget {
  const IdentityApprovalsScreen({super.key});

  static const _blue = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      const Expanded(child: _BirthDateRequestsTab()),
    ]);
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.verified_user_outlined, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin тасдиқлари',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                'Туғилган кун ўзгаришларини назорат қилиш',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _BirthDateRequestsTab extends StatelessWidget {
  const _BirthDateRequestsTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return StreamBuilder<List<BirthDateChangeRequest>>(
      stream: repo.watchPendingBirthDateChangeRequests(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final requests = snap.data ?? const <BirthDateChangeRequest>[];
        if (requests.isEmpty) {
          return const _EmptyState(text: 'Кутилаётган туғилган кун сўрови йўқ');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: requests.length,
          itemBuilder: (_, i) => _BirthDateRequestCard(request: requests[i]),
        );
      },
    );
  }
}

class _BirthDateRequestCard extends StatelessWidget {
  const _BirthDateRequestCard({required this.request});

  final BirthDateChangeRequest request;

  @override
  Widget build(BuildContext context) {
    return _RequestCard(
      icon: Icons.cake_outlined,
      title: 'User: ${request.userId}',
      subtitle:
          'Ҳозирги: ${_dash(request.currentBirthDate)} → Янги: ${_dash(request.requestedBirthDate)}',
      createdAt: request.createdAt,
      actions: [
        OutlinedButton.icon(
          onPressed: () => _reject(context),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Рад этиш'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _approve(context),
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Тасдиқлаш'),
        ),
      ],
    );
  }

  Future<void> _approve(BuildContext context) async {
    final repo = context.read<UserRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.approveBirthDateChange(request);
      messenger.showSnackBar(const SnackBar(
        content: Text('Туғилган кун ўзгариши тасдиқланди'),
        backgroundColor: AppColors.button,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reject(BuildContext context) async {
    final repo = context.read<UserRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.rejectBirthDateChange(request.id);
      messenger.showSnackBar(const SnackBar(
        content: Text('Сўров рад этилди'),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.createdAt,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime? createdAt;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE3F2FD),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(subtitle, style: const TextStyle(height: 1.35)),
                if (createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Юборилган: ${_formatDateTime(createdAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 0, runSpacing: 8, children: actions),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 52, color: AppColors.primaryMid),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(fontSize: 16)),
      ]),
    );
  }
}

String _dash(String value) => value.trim().isEmpty ? '—' : value.trim();

String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
