import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/risk_event.dart';
import '../../../repositories/user_repository.dart';
import '../services/admin_auth_service.dart';

class RiskReviewScreen extends StatelessWidget {
  const RiskReviewScreen({super.key});

  static const _blue = Color(0xFF0D47A1);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      Expanded(
        child: StreamBuilder<List<RiskEvent>>(
          stream: context.read<UserRepository>().watchOpenRiskEvents(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Хатолик: ${snap.error}'));
            }
            final events = snap.data ?? const <RiskEvent>[];
            if (events.isEmpty) {
              return const _EmptyRiskState();
            }
            return ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: events.length,
              itemBuilder: (_, i) => _RiskEventCard(event: events[i]),
            );
          },
        ),
      ),
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
          child: const Icon(Icons.security, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Risk review',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                'Телефон, қурилма ва profile ўзгаришларидаги хавфли сигналлар',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _RiskEventCard extends StatefulWidget {
  const _RiskEventCard({required this.event});

  final RiskEvent event;

  @override
  State<_RiskEventCard> createState() => _RiskEventCardState();
}

class _RiskEventCardState extends State<_RiskEventCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(widget.event.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(_typeIcon(widget.event.type), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _chip(_severityLabel(widget.event.severity), color),
                  _chip(_typeLabel(widget.event.type), Colors.blueGrey),
                ]),
                const SizedBox(height: 8),
                Text(widget.event.message,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text('User: ${_dash(widget.event.userId)}'),
                if (widget.event.deviceId.isNotEmpty)
                  Text('Device: ${widget.event.deviceId}'),
                if (widget.event.meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.event.meta.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
                if (widget.event.createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Вақт: ${_formatDateTime(widget.event.createdAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _busy ? null : _resolve,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 16),
            label: const Text('Resolved'),
          ),
        ]),
      ),
    );
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    final repo = context.read<UserRepository>();
    final auth = context.read<AdminAuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.resolveRiskEvent(
        widget.event.id,
        operatorPhone: auth.phone ?? '',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Risk event ёпилди'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _EmptyRiskState extends StatelessWidget {
  const _EmptyRiskState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_user_outlined,
            size: 54, color: Colors.green.shade400),
        const SizedBox(height: 10),
        const Text('Очиқ risk event йўқ'),
      ]),
    );
  }
}

Color _severityColor(String severity) {
  switch (severity) {
    case 'high':
      return Colors.red;
    case 'medium':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'same_device_new_phone':
      return Icons.phonelink_lock;
    case 'profile_phone_change_request':
      return Icons.phone_forwarded;
    case 'birthdate_change_request':
      return Icons.cake_outlined;
    case 'similar_device_signal_new_install':
      return Icons.manage_search;
    default:
      return Icons.warning_amber;
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'same_device_new_phone':
      return 'Same device/new phone';
    case 'profile_phone_change_request':
      return 'Phone change';
    case 'birthdate_change_request':
      return 'BirthDate change';
    case 'similar_device_signal_new_install':
      return 'Similar device';
    default:
      return type.isEmpty ? 'Risk' : type;
  }
}

String _severityLabel(String severity) {
  switch (severity) {
    case 'high':
      return 'HIGH';
    case 'medium':
      return 'MEDIUM';
    default:
      return 'LOW';
  }
}

String _dash(String value) => value.trim().isEmpty ? '—' : value.trim();

String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
