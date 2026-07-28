import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';

import '../../../models/queue_entry.dart';
import '../../../core/passenger_cancel_block_rules.dart';
import '../../../repositories/local_taxi_block_repository.dart';
import '../../../repositories/marshrut_block_repository.dart';
import '../../../repositories/marshrut_route_price_repository.dart';
import '../../../services/marshrut_pricing_service.dart';
import '../../../repositories/queue_repository.dart';
import '../../../repositories/rides_repository.dart';
import '../../../core/theme/app_theme.dart';

/// Admin web — marshrut taksi monitoring paneli.
/// Faol haydovchilar, navbat, bugungi sayohatlar statistikasi.
class MarshrutAdminScreen extends StatelessWidget {
  const MarshrutAdminScreen({super.key});

  static final _db = FirebaseFirestore.instance;
  static final _time = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('🚌 Маршрут мониторинги'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: [
              Tab(text: 'Фаол ҳайдовчилар'),
              Tab(text: 'Policy'),
              Tab(text: 'Auto-paused'),
              Tab(text: 'Bloklar'),
              Tab(text: 'Бугунги сафарлар'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OnlineDriversTab(db: _db, time: _time),
            const _DispatchPolicyTab(),
            const _PausedDriversTab(),
            const _PassengerBlocksTab(),
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
          .collection('trips')
          .where('taxiType', isEqualTo: 'marshrut')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (ctx, tripsSnap) {
        final activeTripByDriver = <String, Map<String, dynamic>>{};
        for (final doc in tripsSnap.data?.docs ?? const []) {
          final data = doc.data();
          final driverId = (data['acceptedDriverId'] ?? '') as String;
          if (driverId.isNotEmpty) activeTripByDriver[driverId] = data;
        }
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
                final driverId = docs[i].id;
                final updatedAt = d['updatedAt'] as Timestamp?;
                final plannedStartAt = d['plannedStartAt'] as Timestamp?;
                final actualOnlineAt = d['actualOnlineAt'] as Timestamp?;
                final queueEligibleAt = d['queueEligibleAt'] as Timestamp?;
                final seatsLeft = d['seatsLeft'] ?? 0;
                final isBusy = d['isBusy'] as bool? ?? false;
                final todayTrips = (d['todayTrips'] as num?)?.toInt() ?? 0;
                final todayRejects = (d['todayRejects'] as num?)?.toInt() ?? 0;
                final todayTimeouts = (d['todayTimeouts'] as num?)?.toInt() ?? 0;
                final stops = (d['stops'] as List?)?.join(' → ') ?? '—';
                final activeTrip = activeTripByDriver[driverId];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isBusy
                          ? Colors.orange.shade100
                          : AppColors.tickerShell,
                      child: Icon(
                        isBusy ? Icons.person_pin : Icons.directions_bus,
                        color: isBusy ? Colors.orange : AppColors.primary,
                      ),
                    ),
                    title: Text(
                      '${d['name'] ?? '—'}  •  ${d['car'] ?? ''} ${d['plate'] ?? ''}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📍 $stops'),
                        Text(
                          '🪑 Бўш: $seatsLeft  •  ${isBusy ? '🔴 Band' : '🟢 Bo\'sh'}  •  Йўналиш: ${d['direction'] == 'backward' ? '↩ Тескари' : '→ Олдинга'}',
                        ),
                        if (activeTrip != null)
                          Text(
                            '🚕 Faol safar: ${activeTrip['pickupMfy'] ?? '?'} → ${activeTrip['dropoffMfy'] ?? '?'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          '⏰ Режа: ${_fmtTs(plannedStartAt)}  •  Онлайн: ${_fmtTs(actualOnlineAt)}  •  Навбат: ${_fmtTs(queueEligibleAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '📊 Бугун: $todayTrips сафар  •  Рад: $todayRejects  •  Timeout: $todayTimeouts',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (updatedAt != null)
                          Text(
                            'Heartbeat: ${time.format(updatedAt.toDate())}',
                            style:
                                const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                    trailing: Text(
                      d['phone']?.toString() ?? driverId,
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _fmtTs(Timestamp? ts) => ts == null ? '—' : time.format(ts.toDate());
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
                const _PassengerCancelBlockPolicyCard(),
                const SizedBox(height: 12),
                const _MarshrutTariffPolicyCard(),
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
          child:
              const Icon(Icons.pause_circle_outline, color: Colors.deepPurple),
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
}

// ─── Yo'lovchi bloklari ────────────────────────────────────────────────────

class _PassengerBlocksTab extends StatefulWidget {
  const _PassengerBlocksTab();

  @override
  State<_PassengerBlocksTab> createState() => _PassengerBlocksTabState();
}

enum _PassengerBlockKind { marshrut, localTaxi }

class _PassengerBlocksTabState extends State<_PassengerBlocksTab> {
  final _phoneCtrl = TextEditingController();
  final _marshrutRepo = MarshrutBlockRepository();
  final _localRepo = LocalTaxiBlockRepository();
  _PassengerBlockKind _kind = _PassengerBlockKind.marshrut;
  bool _clearing = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _clearByPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() => _clearing = true);
    try {
      if (_kind == _PassengerBlockKind.marshrut) {
        await _marshrutRepo.clearBlock(phone);
      } else {
        await _localRepo.clearBlock(phone);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Blok bekor qilindi'),
            backgroundColor: Colors.green,
          ),
        );
        _phoneCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<_PassengerBlockKind>(
            segments: const [
              ButtonSegment(
                value: _PassengerBlockKind.marshrut,
                label: Text('Marshrut'),
              ),
              ButtonSegment(
                value: _PassengerBlockKind.localTaxi,
                label: Text('Local taxi'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              setState(() => _kind = s.first);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (blokni bekor qilish)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _clearing ? null : _clearByPhone,
                child: _clearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Tozalash'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _kind == _PassengerBlockKind.marshrut
              ? StreamBuilder<List<MarshrutBlockedUserEntry>>(
                  stream: _marshrutRepo.watchActiveBlocks(),
                  builder: (ctx, snap) =>
                      _buildBlockList<MarshrutBlockedUserEntry>(
                    snap: snap,
                    label: 'marshrut',
                    userId: (e) => e.userId,
                    blockedUntil: (e) => e.blockedUntil,
                    cancelCount: (e) => e.cancelCount,
                    onClear: (id) =>
                        _marshrutRepo.clearBlock(id).catchError((_) {}),
                  ),
                )
              : StreamBuilder<List<LocalTaxiBlockedUserEntry>>(
                  stream: _localRepo.watchActiveBlocks(),
                  builder: (ctx, snap) =>
                      _buildBlockList<LocalTaxiBlockedUserEntry>(
                    snap: snap,
                    label: 'local taxi',
                    userId: (e) => e.userId,
                    blockedUntil: (e) => e.blockedUntil,
                    cancelCount: (e) => e.cancelCount,
                    onClear: (id) =>
                        _localRepo.clearBlock(id).catchError((_) {}),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBlockList<T>({
    required AsyncSnapshot<List<T>> snap,
    required String label,
    required String Function(T) userId,
    required DateTime Function(T) blockedUntil,
    required int Function(T) cancelCount,
    required void Function(String) onClear,
  }) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = snap.data ?? const [];
    if (list.isEmpty) {
      return Center(
        child: Text(
          'Faol $label bloklari yo\'q',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final e = list[i];
        final left =
            blockedUntil(e).difference(DateTime.now()).inMinutes + 1;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(userId(e)),
            subtitle: Text(
              'Qolgan: ~$left daq  •  Bekor soni: ${cancelCount(e)}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Blokni bekor qilish',
              onPressed: () => onClear(userId(e)),
            ),
          ),
        );
      },
    );
  }
}

class _PassengerCancelBlockPolicyCard extends StatelessWidget {
  const _PassengerCancelBlockPolicyCard();

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
              'Yo\'lovchi bekor qilish bloki',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Marshrut: faqat qabul qilingan safardan keyin bekor (kutish bekor — blok yo\'q). '
              'Local taxi: qidiruv paytida bekor. '
              'Маҳаллий: қабулдан кейин 3-бекор — енгил огоҳ, 4 — қаттиқ '
              '(қизил), 5 — 15 дақ блок. Маршрут: алоҳида қоида '
              '(${PassengerCancelBlockRules.cancelLimit} / '
              '${PassengerCancelBlockRules.blockMinutes} дақ). '
              'Ҳисоб CF да; local_taxi_block ёзуви фақат admin/CF.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarshrutTariffPolicyCard extends StatefulWidget {
  const _MarshrutTariffPolicyCard();

  @override
  State<_MarshrutTariffPolicyCard> createState() =>
      _MarshrutTariffPolicyCardState();
}

class _MarshrutTariffPolicyCardState extends State<_MarshrutTariffPolicyCard> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _priceRepo = MarshrutRoutePriceRepository();
  bool _busy = false;

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveRoute() async {
    final price = int.tryParse(_priceCtrl.text.trim());
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    if (price == null || price <= 0 || from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('From / To / narx to\'g\'ri kiriting')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await MarshrutPricingService.setByAdmin(
        from: from,
        to: to,
        price: price,
      );
      final propagated = (res['propagated'] as num?)?.toInt() ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Yo\'nalish narxi saqlandi ($propagated faol reysga qo\'llandi)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _prefill(MarshrutRoutePrice r) {
    _fromCtrl.text = r.from;
    _toCtrl.text = r.to;
    _priceCtrl.text = '${r.price}';
    setState(() {});
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
              'Marshrut yo\'nalish narxlari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Narxni birinchi haydovchi belgilaydi. Bu yerda admin tahrir '
              'qiladi — o\'zgarish darhol faol reyslarga qo\'llanadi.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(
                labelText: 'Qayerdan (MFY)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(
                labelText: 'Qayerga (MFY)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Narx / o\'rin (сўм)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _saveRoute,
                child: const Text('Narxni saqlash'),
              ),
            ),
            const Divider(height: 24),
            StreamBuilder<List<MarshrutRoutePrice>>(
              stream: _priceRepo.watchAll(),
              builder: (ctx, snap) {
                final routes = snap.data ?? const <MarshrutRoutePrice>[];
                if (routes.isEmpty) {
                  return Text(
                    'Hali yo\'nalish narxi belgilanmagan.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Belgilangan yo\'nalishlar:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ...routes.map(
                      (r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r.from} → ${r.to}'),
                        subtitle: Text(
                          '${formatMoney(r.price)}'
                          '${r.lockedByAdmin ? ' • admin' : ''}'
                          '${r.setByName.isNotEmpty ? ' • ${r.setByName}' : ''}',
                        ),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () => _prefill(r),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
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
        return AppColors.primary;
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
        final todayStart = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
        final docs = snap.data!.docs.where((d) {
          final ts = d.data()['createdAt'];
          if (ts is! Timestamp) return false;
          return !ts.toDate().isBefore(todayStart);
        }).toList();
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
        final pending =
            docs.where((d) => d.data()['status'] == 'pending').length;
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
