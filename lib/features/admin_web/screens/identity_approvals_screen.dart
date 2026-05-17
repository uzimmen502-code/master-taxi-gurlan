import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/identity_change_request.dart';
import '../../../repositories/user_repository.dart';

class IdentityApprovalsScreen extends StatelessWidget {
  const IdentityApprovalsScreen({super.key});

  static const _blue = Color(0xFF0D47A1);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        _header(),
        const Material(
          color: Colors.white,
          child: TabBar(
            labelColor: _blue,
            unselectedLabelColor: Colors.black54,
            tabs: [
              Tab(icon: Icon(Icons.cake_outlined), text: 'Туғилган кун'),
              Tab(icon: Icon(Icons.phonelink_lock), text: 'Қурилма/рақам'),
            ],
          ),
        ),
        const Expanded(
          child: TabBarView(
            children: [
              _BirthDateRequestsTab(),
              _DeviceRequestsTab(),
            ],
          ),
        ),
      ]),
    );
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
                'Туғилган кун, телефон рақам ва қурилма ўзгаришларини назорат қилиш',
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
        backgroundColor: Colors.green,
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

class _DeviceRequestsTab extends StatelessWidget {
  const _DeviceRequestsTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return StreamBuilder<List<DeviceChangeRequest>>(
      stream: repo.watchPendingDeviceChangeRequests(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final requests = snap.data ?? const <DeviceChangeRequest>[];
        if (requests.isEmpty) {
          return const _EmptyState(text: 'Кутилаётган қурилма/рақам сўрови йўқ');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: requests.length,
          itemBuilder: (_, i) => _DeviceRequestCard(request: requests[i]),
        );
      },
    );
  }
}

class _DeviceRequestCard extends StatelessWidget {
  const _DeviceRequestCard({required this.request});

  final DeviceChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final current = request.currentPhone.isNotEmpty
        ? request.currentPhone
        : request.currentUserId;
    final requested = request.requestedPhone.isNotEmpty
        ? request.requestedPhone
        : request.requestedUserId;
    return _RequestCard(
      icon: Icons.phonelink_lock,
      title: 'Қурилма: ${request.deviceId}',
      subtitle:
          'Ҳозирги рақам: ${_dash(current)} → Янги рақам: ${_dash(requested)}'
          '\nСабаб: ${_reasonLabel(request.reason)}'
          '\nDevice signal: ${_deviceSignalSummary(request.signals)}',
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
      await repo.approveDeviceChange(request);
      messenger.showSnackBar(const SnackBar(
        content: Text('Қурилма/рақам ўзгариши тасдиқланди'),
        backgroundColor: Colors.green,
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
      await repo.rejectDeviceChange(request.id);
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
            child: Icon(icon, color: const Color(0xFF0D47A1)),
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
        Icon(Icons.check_circle_outline, size: 52, color: Colors.green.shade400),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(fontSize: 16)),
      ]),
    );
  }
}

String _dash(String value) => value.trim().isEmpty ? '—' : value.trim();

String _reasonLabel(String reason) {
  switch (reason) {
    case 'profile_phone_change':
      return 'Профилдан телефон рақамни алмаштириш';
    case 'same_device_new_phone':
      return 'Шу қурилмадан бошқа рақам билан кириш';
    default:
      return reason.isEmpty ? '—' : reason;
  }
}

String _deviceSignalSummary(Map<String, dynamic> signals) {
  if (signals.isEmpty) return '—';
  final platform = signals['platform']?.toString() ?? '';
  final model = signals['model']?.toString() ??
      signals['productName']?.toString() ??
      signals['browserName']?.toString() ??
      '';
  final os = signals['osVersion']?.toString() ??
      signals['systemVersion']?.toString() ??
      signals['displayVersion']?.toString() ??
      '';
  return [platform, model, os].where((v) => v.trim().isNotEmpty).join(' • ');
}

String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
