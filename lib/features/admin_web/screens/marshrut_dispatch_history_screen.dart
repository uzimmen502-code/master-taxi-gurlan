import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/active_trip.dart';
import '../../../models/marshrut_dispatch_event.dart';
import '../../../repositories/rides_repository.dart';
import '../services/admin_auth_service.dart';
import '../../../core/theme/app_theme.dart';

class MarshrutDispatchHistoryScreen extends StatelessWidget {
  const MarshrutDispatchHistoryScreen({super.key});

  static const _blue = AppColors.primary;

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
              Tab(icon: Icon(Icons.pending_actions), text: 'Active requests'),
              Tab(icon: Icon(Icons.timeline), text: 'History'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            const _ActiveMarshrutTripsTab(),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('marshrut_dispatch_events')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Хатолик: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Dispatch history ҳали йўқ'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(18),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    return _DispatchEventCard(
                      event: MarshrutDispatchEvent.fromDoc(doc),
                      cancelledBy: data['cancelledBy'] as String?,
                    );
                  },
                );
              },
            ),
          ]),
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
          child: const Icon(Icons.timeline, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Marshrut dispatch history',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                '1-навбат → … → 7-навбат таклифлари ва натижалари',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DispatchEventCard extends StatelessWidget {
  const _DispatchEventCard({
    required this.event,
    this.cancelledBy,
  });

  final MarshrutDispatchEvent event;
  final String? cancelledBy;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(event.type);
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
            child: Icon(_typeIcon(event.type), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _chip(_typeLabel(event.type, cancelledBy: cancelledBy), color),
                  _chip(
                    '${event.dispatchAttempt}/${event.dispatchTotal}-навбат',
                    Colors.blueGrey,
                  ),
                  _chip(event.dispatchMode, Colors.indigo),
                ]),
                const SizedBox(height: 8),
                Text(
                  '${_dash(event.pickupMfy)} → ${_dash(event.dropoffMfy)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text('User: ${_dash(event.userPhone)}'),
                Text(
                  'Driver: ${_dash(event.driverName)} (${_dash(event.driverPhone)})',
                ),
                if (event.offerTimeoutSeconds > 0)
                  Text('Offer timeout: ${event.offerTimeoutSeconds} сек'),
                if (event.timeoutStreak > 0)
                  Text(
                    'Timeout streak: ${event.timeoutStreak}'
                    '${event.timeoutAutoPauseStreak > 0 ? ' / ${event.timeoutAutoPauseStreak}' : ''}',
                  ),
                Text('Trip: ${_dash(event.tripId)}'),
                if (event.dispatchSessionId.isNotEmpty)
                  Text('Session: ${event.dispatchSessionId}'),
                if (event.scheduleId.isNotEmpty)
                  Text('Schedule: ${event.scheduleId}'),
                if (event.createdAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Вақт: ${_formatDateTime(event.createdAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
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

class _ActiveMarshrutTripsTab extends StatelessWidget {
  const _ActiveMarshrutTripsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActiveTrip>>(
      stream:
          context.read<RidesRepository>().watchActiveMarshrutTripsForAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final trips = snap.data ?? const <ActiveTrip>[];
        if (trips.isEmpty) {
          return const Center(child: Text('Актив marshrut request йўқ'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: trips.length,
          itemBuilder: (_, i) => _ActiveTripCard(trip: trips[i]),
        );
      },
    );
  }
}

class _ActiveTripCard extends StatefulWidget {
  const _ActiveTripCard({required this.trip});

  final ActiveTrip trip;

  @override
  State<_ActiveTripCard> createState() => _ActiveTripCardState();
}

class _ActiveTripCardState extends State<_ActiveTripCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.trip.status == 'accepted' ? AppColors.primary : Colors.orange;
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
            child: Icon(Icons.local_taxi, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _chip(widget.trip.status, color),
                  _chip('active', Colors.blueGrey),
                ]),
                const SizedBox(height: 8),
                Text(
                  '${_dash(widget.trip.pickupMfy)} → ${_dash(widget.trip.dropoffMfy)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text('User: ${_dash(widget.trip.userPhone)}'),
                Text(
                  'Driver: ${_dash(widget.trip.driverName)} (${_dash(widget.trip.driverPhone)})',
                ),
                if (widget.trip.offerTimeoutSeconds > 0)
                  Text('Offer timeout: ${widget.trip.offerTimeoutSeconds} сек'),
                if (widget.trip.expiresAt != null)
                  Text(
                    'Expires: ${_formatDateTime(widget.trip.expiresAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                Text('Trip: ${widget.trip.id}'),
                if (widget.trip.createdAt != null)
                  Text(
                    'Яратилган: ${_formatDateTime(widget.trip.createdAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.trip.status == 'accepted') ...[
                ElevatedButton.icon(
                  onPressed: _busy ? null : _complete,
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Completed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Admin cancel'),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request’ни бекор қилиш'),
        content: const Text(
          'Бу active marshrut request admin томонидан cancelled қилинади. Давом этасизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа, бекор қилиш'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    final repo = context.read<RidesRepository>();
    final auth = context.read<AdminAuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.adminCancelMarshrutTrip(
        tripId: widget.trip.id,
        operatorPhone: auth.phone ?? '',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Request cancelled қилинди'),
        backgroundColor: AppColors.button,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сафарни якунлаш'),
        content: const Text(
          'Бу accepted marshrut trip admin томонидан completed қилинади. Давом этасизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа, якунлаш'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    final repo = context.read<RidesRepository>();
    final auth = context.read<AdminAuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.adminCompleteMarshrutTrip(
        tripId: widget.trip.id,
        driverId: widget.trip.driverId,
        operatorPhone: auth.phone ?? '',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Trip completed қилинди'),
        backgroundColor: AppColors.button,
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

Color _typeColor(String type) {
  switch (type) {
    case 'accepted':
      return AppColors.primary;
    case 'rejected':
      return Colors.orange;
    case 'timeout':
      return Colors.red;
    case 'cancelled':
      return Colors.blueGrey;
    case 'completed':
    case 'admin_completed':
      return AppColors.primary;
    case 'driver_auto_paused':
      return Colors.deepPurple;
    default:
      return Colors.blue;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'accepted':
      return Icons.check_circle_outline;
    case 'rejected':
      return Icons.close;
    case 'timeout':
      return Icons.timer_off;
    case 'cancelled':
      return Icons.cancel_outlined;
    case 'completed':
    case 'admin_completed':
      return Icons.done_all;
    case 'driver_auto_paused':
      return Icons.pause_circle_outline;
    default:
      return Icons.send;
  }
}

String _typeLabel(String type, {String? cancelledBy}) {
  switch (type) {
    case 'offered':
      return 'Таклиф юборилди';
    case 'accepted':
      return 'Қабул қилинди';
    case 'rejected':
      return 'Рад этилди';
    case 'timeout':
      return 'Жавоб бермади';
    case 'cancelled':
      final by = cancelledBy ?? 'user';
      if (by == 'admin') return '🔧 Admin бекор қилди';
      if (by == 'driver') return '🚌 Ҳайдовчи бекор қилди';
      return '👤 Йўловчи бекор қилди';
    case 'passenger_cancel_after_accept':
      return '👤 Йўловчи қабулдан кейин бекор қилди';
    case 'admin_cancelled':
      return 'Admin бекор қилди';
    case 'completed':
      return 'Сафар якунланди';
    case 'admin_completed':
      return 'Admin якунлади';
    case 'driver_auto_paused':
      return 'Driver auto-paused';
    default:
      return type;
  }
}

String _dash(String value) => value.trim().isEmpty ? '—' : value.trim();

String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
