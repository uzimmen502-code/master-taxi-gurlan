import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/queue_entry.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';

/// Admin web — marshrut taksi monitoring paneli.
/// Faol haydovchilar, navbat, bugungi sayohatlar statistikasi.
class MarshrutAdminScreen extends StatelessWidget {
  const MarshrutAdminScreen({super.key});

  static final _db = FirebaseFirestore.instance;
  static final _time = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          title: const Text('🚌 Маршрут мониторинги'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Фаол ҳайдовчилар'),
              Tab(text: 'Policy'),
              Tab(text: 'Auto-paused'),
              Tab(text: 'Бугунги сафарлар'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OnlineDriversTab(db: _db, time: _time),
            const _DispatchPolicyTab(),
            const _PausedDriversTab(),
            _TodayTripsTab(db: _db, time: _time),
          ],
        ),
      ),
    );
  }
}

// ─── Фаол ҳайдовчилар ─────────────────────────────────────────────────────

class _OnlineDriversTab extends StatelessWidget {
  const _OnlineDriversTab({required this.db, required this.time});
  final FirebaseFirestore db;
  final DateFormat time;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('drivers')
          .where('isOnline', isEqualTo: true)
          .where('taxiType', isEqualTo: 'marshrut')
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Ҳозир онлайн маршрут ҳайдовчилари йўқ',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final updatedAt = d['updatedAt'] as Timestamp?;
            final seatsLeft = d['seatsLeft'] ?? 0;
            final stops = (d['stops'] as List?)?.join(' → ') ?? '—';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.directions_bus, color: Colors.green),
                ),
                title: Text(
                  '${d['name'] ?? '—'}  •  ${d['car'] ?? ''} ${d['plate'] ?? ''}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📍 $stops'),
                    Text(
                      '🪑 Бўш жой: $seatsLeft  •  Йўналиш: ${d['direction'] == 'backward' ? '↩ Тескари' : '→ Олдинга'}',
                    ),
                    if (updatedAt != null)
                      Text(
                        'Heartbeat: ${time.format(updatedAt.toDate())}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                trailing: Text(
                  d['phone']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Dispatch policy созламалари ───────────────────────────────────────────

class _DispatchPolicyTab extends StatelessWidget {
  const _DispatchPolicyTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RidesRepository>();
    return StreamBuilder<int>(
      stream: repo.watchMarshrutTimeoutAutoPauseStreak(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<int>(
          stream: repo.watchMarshrutOfferTimeoutSeconds(),
          builder: (ctx, offerSnap) {
            if (!offerSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OfferTimeoutPolicyCard(currentValue: offerSnap.data ?? 15),
                const SizedBox(height: 12),
                _TimeoutPolicyCard(currentValue: snap.data ?? 3),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Қоида қандай ишлайди?',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Driver dispatch таклифини белгиланган вақт ичида қабул қилмаса timeout бўлади. Timeout белгиланган марта кетма-кет такрорланса, тизим driver’ни вақтинча навбатдан чиқаради.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _OfferTimeoutPolicyCard extends StatefulWidget {
  const _OfferTimeoutPolicyCard({required this.currentValue});

  final int currentValue;

  @override
  State<_OfferTimeoutPolicyCard> createState() =>
      _OfferTimeoutPolicyCardState();
}

class _OfferTimeoutPolicyCardState extends State<_OfferTimeoutPolicyCard> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue.toString());
  }

  @override
  void didUpdateWidget(covariant _OfferTimeoutPolicyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && oldWidget.currentValue != widget.currentValue) {
      _ctrl.text = widget.currentValue.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driver offer timeout',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Driver’га dispatch таклифи неча секунд кўриниб туради.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Секунд',
                      border: OutlineInputBorder(),
                      helperText: '5-120 оралиғида',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Сақлаш'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null || value < 5 || value > 120) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Қиймат 5 дан 120 секундгача бўлиши керак'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _busy = true);
    try {
      await context.read<RidesRepository>().setMarshrutOfferTimeoutSeconds(
            value,
          );
      messenger.showSnackBar(const SnackBar(
        content: Text('Offer timeout сақланди'),
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
}

class _TimeoutPolicyCard extends StatefulWidget {
  const _TimeoutPolicyCard({required this.currentValue});

  final int currentValue;

  @override
  State<_TimeoutPolicyCard> createState() => _TimeoutPolicyCardState();
}

class _TimeoutPolicyCardState extends State<_TimeoutPolicyCard> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue.toString());
  }

  @override
  void didUpdateWidget(covariant _TimeoutPolicyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && oldWidget.currentValue != widget.currentValue) {
      _ctrl.text = widget.currentValue.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Timeout auto-pause threshold',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Неча марта кетма-кет timeout бўлса driver навбатдан вақтинча чиқарилади.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Timeout сони',
                      border: OutlineInputBorder(),
                      helperText: '1-20 оралиғида',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: const Text('Сақлаш'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null || value < 1 || value > 20) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Қиймат 1 дан 20 гача бўлиши керак'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _busy = true);
    try {
      await context.read<RidesRepository>().setMarshrutTimeoutAutoPauseStreak(
            value,
          );
      messenger.showSnackBar(const SnackBar(
        content: Text('Dispatch policy сақланди'),
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
}

// ─── Auto-paused ҳайдовчилар ────────────────────────────────────────────────

class _PausedDriversTab extends StatelessWidget {
  const _PausedDriversTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<QueueRepository>();
    return StreamBuilder<List<QueueEntry>>(
      stream: repo.watchAutoPausedMarshrutDrivers(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final drivers = snap.data ?? const <QueueEntry>[];
        if (drivers.isEmpty) {
          return const Center(
            child: Text(
              'Auto-paused ҳайдовчи йўқ',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: drivers.length,
          itemBuilder: (_, i) => _PausedDriverCard(driver: drivers[i]),
        );
      },
    );
  }
}

class _PausedDriverCard extends StatefulWidget {
  const _PausedDriverCard({required this.driver});

  final QueueEntry driver;

  @override
  State<_PausedDriverCard> createState() => _PausedDriverCardState();
}

class _PausedDriverCardState extends State<_PausedDriverCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.shade50,
          child: const Icon(Icons.pause_circle_outline,
              color: Colors.deepPurple),
        ),
        title: Text(
          '${widget.driver.driverName}  •  ${widget.driver.car} ${widget.driver.plate}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📞 ${widget.driver.driverPhone}'),
            Text('🪑 Бўш жой: ${widget.driver.seatsLeft}'),
            const Text(
              'Сабаб: policy бўйича кетма-кет dispatch timeout',
              style: TextStyle(color: Colors.deepPurple),
            ),
          ],
        ),
        trailing: ElevatedButton.icon(
          onPressed: _busy ? null : _reactivate,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: const Text('Қайта active'),
        ),
        isThreeLine: true,
      ),
    );
  }

  Future<void> _reactivate() async {
    setState(() => _busy = true);
    final repo = context.read<QueueRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.reactivateAutoPausedDriver(widget.driver.driverId);
      messenger.showSnackBar(const SnackBar(
        content: Text('Ҳайдовчи қайта навбатга қўйилди'),
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
}

// ─── Бугунги сафарлар ─────────────────────────────────────────────────────

class _TodayTripsTab extends StatelessWidget {
  const _TodayTripsTab({
    required this.db,
    required this.time,
  });
  final FirebaseFirestore db;
  final DateFormat time;

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.grey;
      case 'cancelled':
        return Colors.red.shade300;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('trips')
          .where('taxiType', isEqualTo: 'marshrut')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Бугун маршрут сафарлари йўқ',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        final accepted =
            docs.where((d) => d.data()['status'] == 'accepted').length;
        final pending = docs.where((d) => d.data()['status'] == 'pending').length;
        final rejected =
            docs.where((d) => d.data()['status'] == 'rejected').length;

        return Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat('${docs.length}', 'Жами', Colors.blue),
                  _Stat('$accepted', 'Қабул', Colors.green),
                  _Stat('$pending', 'Кутиш', Colors.orange),
                  _Stat('$rejected', 'Рад', Colors.red),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final status = d['status'] ?? '';
                  final createdAt = d['createdAt'] as Timestamp?;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: _statusColor(status.toString())
                            .withValues(alpha: 0.15),
                        child: Icon(
                          Icons.route,
                          size: 16,
                          color: _statusColor(status.toString()),
                        ),
                      ),
                      title: Text(
                        '${d['pickupMfy'] ?? '?'} → ${d['dropoffMfy'] ?? '?'}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '📞 ${d['userPhone'] ?? '—'}  •  ${d['driverName'] ?? '—'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(status.toString())
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status.toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: _statusColor(status.toString()),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (createdAt != null)
                            Text(
                              time.format(createdAt.toDate()),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      );
}
