import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/entertainment_repository.dart';
import 'entertainment_catalog_tab.dart';
import '../../../core/theme/app_theme.dart';

/// Admin web — shaharlararo taksi: haydovchilar, bronlar, statistika.
class IntercityAdminScreen extends StatelessWidget {
  const IntercityAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => EntertainmentRepository(),
      child: DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('Shaharlararo taksi'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Haydovchilar'),
              Tab(text: 'Bronlar'),
              Tab(text: 'Kino'),
              Tab(text: 'Statistika'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _DriversTab(),
            const _BookingsTab(),
            const EntertainmentCatalogTab(),
            const _StatsTab(),
          ],
        ),
      ),
    ),
    );
  }
}

// ─── Tab 1: Haydovchilar ───────────────────────────────────────────────────

class _DriversTab extends StatefulWidget {
  const _DriversTab();
  @override
  State<_DriversTab> createState() => _DriversTabState();
}

class _DriversTabState extends State<_DriversTab> {
  static final _db = FirebaseFirestore.instance;
  bool _showAllDays = false;

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDriverDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final todayKey = _dateKey(DateTime.now());
  final filtered = _showAllDays
      ? docs
      : docs.where((doc) {
          final d = doc.data();
          final scheduleDate = (d['scheduleDate'] as String?)?.trim() ?? '';
          if (scheduleDate.isEmpty) {
            return d['isActive'] == true;
          }
          return scheduleDate == todayKey;
        }).toList(growable: false);

    final byPhone = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in filtered) {
      final phone = phoneDigits((doc.data()['phone'] ?? doc.id).toString());
      if (phone.length < 9) continue;
      final existing = byPhone[phone];
      if (existing == null) {
        byPhone[phone] = doc;
        continue;
      }
      final existingActive = existing.data()['isActive'] == true;
      final currentActive = doc.data()['isActive'] == true;
      if (currentActive && !existingActive) {
        byPhone[phone] = doc;
      }
    }
    final unique = byPhone.values.toList()
      ..sort((a, b) {
        final aa = a.data()['isActive'] == true;
        final bb = b.data()['isActive'] == true;
        if (aa != bb) return aa ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    return unique;
  }

  /// Қолган / жами ўринлар (масalan `2/4`).
  static String _seatsLabel(Map<String, dynamic> d) {
    final left = (d['seats'] as num?)?.toInt() ?? 0;
    var cap = (d['seatCapacity'] as num?)?.toInt() ?? 0;
    if (cap < left) cap = left;
    if (cap <= 0) return '$left';
    return '$left/$cap';
  }

  /// Admin toggle — `intercity_drivers` + `schedules` + `queue` синхрон.
  Future<void> _toggleActive(
    String id,
    bool current,
    Map<String, dynamic> data,
  ) async {
    final next = !current;
    final batch = _db.batch();
    batch.set(
      _db.collection('intercity_drivers').doc(id),
      {
        'isActive': next,
        if (!next) 'isOnPanel': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (!next) {
      final scheduleDate =
          (data['scheduleDate'] as String?)?.trim() ?? _dateKey(DateTime.now());
      final sched = await _db
          .collection('schedules')
          .where('driverId', isEqualTo: id)
          .where('taxiType', isEqualTo: 'intercity')
          .where('date', isEqualTo: scheduleDate)
          .where('isActive', isEqualTo: true)
          .get();
      for (final doc in sched.docs) {
        batch.update(doc.reference, {'isActive': false});
      }
      batch.set(
        _db.collection('queue').doc(id),
        {
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> _addDriver(BuildContext context) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final plate = TextEditingController();
    final from = TextEditingController();
    final to = TextEditingController();
    final price = TextEditingController();
    int seats = 4;
    int hour = 8;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Yangi haydovchi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Ismi'),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                TextField(
                  controller: plate,
                  decoration: const InputDecoration(labelText: 'Mashina raqami'),
                ),
                TextField(
                  controller: from,
                  decoration: const InputDecoration(labelText: 'Qayerdan'),
                ),
                TextField(
                  controller: to,
                  decoration: const InputDecoration(labelText: 'Qayerga'),
                ),
                TextField(
                  controller: price,
                  decoration: const InputDecoration(labelText: "Narx (сўм)"),
                  keyboardType: TextInputType.number,
                ),
                Row(
                  children: [
                    const Text('Joylar: '),
                    DropdownButton<int>(
                      value: seats,
                      items: [1, 2, 3, 4]
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n'),
                              ))
                          .toList(),
                      onChanged: (v) => ss(() => seats = v ?? 4),
                    ),
                    const SizedBox(width: 12),
                    const Text('Soat: '),
                    DropdownButton<int>(
                      value: hour,
                      items: List.generate(16, (i) => i + 5)
                          .map((h) => DropdownMenuItem(
                                value: h,
                                child: Text('$h:00'),
                              ))
                          .toList(),
                      onChanged: (v) => ss(() => hour = v ?? 8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.isEmpty || phone.text.isEmpty) return;
                final uid = phone.text.replaceAll(RegExp(r'[^\d]'), '');
                if (uid.isEmpty) return;
                final today = _dateKey(DateTime.now());
                await _db.collection('intercity_drivers').doc(uid).set({
                  'name': name.text,
                  'phone': phone.text,
                  'phoneDigits': uid,
                  'plate': plate.text,
                  'from': from.text,
                  'to': to.text,
                  'routeLabel': '${from.text} → ${to.text}',
                  'price': int.tryParse(price.text) ?? 0,
                  'seatCapacity': seats,
                  'seats': seats,
                  'hour': hour,
                  'scheduleDate': today,
                  'isActive': true,
                  'isOnPanel': false,
                  'rating': 4.5,
                  'parcel': false,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text("Qo'shish"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilterChip(
                label: Text(_showAllDays ? 'Barcha kunlar' : 'Faqat bugun'),
                selected: !_showAllDays,
                onSelected: (_) => setState(() => _showAllDays = !_showAllDays),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Yangilash',
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: () => _addDriver(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Haydovchi qo'shish"),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection('intercity_drivers')
                .orderBy('isActive', descending: true)
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(child: Text('Xato: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = _filterDriverDocs(snap.data!.docs);
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    _showAllDays
                        ? "Haydovchi yo'q"
                        : "Bugun faol haydovchi yo'q",
                    style: const TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final active = d['isActive'] == true;
                  final scheduleDate = (d['scheduleDate'] as String?)?.trim() ?? '';
                  final kino = d['entertainmentAllowed'] == true;
                  final id = docs[i].id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: active
                            ? AppColors.tickerShell
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.directions_car,
                          color: active ? AppColors.primary : Colors.grey,
                        ),
                      ),
                      title: Text(
                        '${d['name'] ?? '-'}  -  ${d['plate'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${d['phone'] ?? ''}\n'
                        '${d['from'] ?? '?'} -> ${d['to'] ?? '?'}  '
                        '${d['hour'] ?? '?'}:00  '
                        '${_seatsLabel(d)} joy  '
                        "${formatMoney(d['price'] ?? 0)}\n"
                        '${scheduleDate.isNotEmpty ? 'Sana: $scheduleDate  ' : ''}'
                        '${kino ? '🎬 Kino ruxsati: yoqilgan' : '🎬 Kino: o‘chiq'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Kino',
                                  style: TextStyle(fontSize: 9)),
                              Switch(
                                value: kino,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) async {
                                  try {
                                    await context
                                        .read<EntertainmentRepository>()
                                        .setDriverEntertainmentAllowed(id, v);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Kino: $e'),
                                        backgroundColor: Colors.red.shade700,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          Switch(
                            value: active,
                            activeTrackColor: AppColors.primary,
                            onChanged: (_) => _toggleActive(id, active, d),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Tab 2: Bronlar ────────────────────────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  const _BookingsTab();
  static final _db = FirebaseFirestore.instance;
  static final _date = DateFormat('dd.MM HH:mm');

  Color _color(String s) {
    switch (s) {
      case 'confirmed':
        return AppColors.primary;
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'expired':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _label(String s) {
    switch (s) {
      case 'confirmed':
        return 'Tasdiqlangan';
      case 'pending':
        return 'Kutilmoqda';
      case 'completed':
        return 'Bajarildi';
      case 'cancelled':
        return 'Bekor';
      case 'expired':
        return "Muddati o'tdi";
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('intercity_bookings')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Xato: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              "Bron yo'q",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final s = d['status'] as String? ?? '';
            final ts = d['createdAt'] as Timestamp?;
            return Card(
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: _color(s).withValues(alpha: 0.15),
                  child: Icon(
                    Icons.confirmation_number,
                    size: 16,
                    color: _color(s),
                  ),
                ),
                title: Text(
                  '${d['fromCity'] ?? '?'} -> ${d['toCity'] ?? '?'}  -  ${d['passengers'] ?? 1} ta',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  '${d['userName'] ?? '-'}  ${d['userPhone'] ?? ''}\n'
                  '${d['driverName'] ?? '-'}  ${formatMoney(d['totalAmount'] ?? 0)}',
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
                        color: _color(s).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _label(s),
                        style: TextStyle(
                          fontSize: 10,
                          color: _color(s),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ts != null)
                      Text(
                        _date.format(ts.toDate()),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                  ],
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

// ─── Tab 3: Statistika ─────────────────────────────────────────────────────

class _StatsTab extends StatelessWidget {
  const _StatsTab();
  static final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('intercity_bookings').snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Xato: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        var total = 0;
        var confirmed = 0;
        var cancelled = 0;
        var revenue = 0;
        for (final doc in docs) {
          final d = doc.data();
          final s = d['status'] as String? ?? '';
          total++;
          if (s == 'confirmed' || s == 'completed') {
            confirmed++;
            revenue += (d['totalAmount'] as num?)?.toInt() ?? 0;
          }
          if (s == 'cancelled') cancelled++;
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Umumiy statistika',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _Stat('Jami bronlar', '$total ta', Colors.blue),
              _Stat('Tasdiqlangan', '$confirmed ta', Colors.green),
              _Stat('Bekor qilingan', '$cancelled ta', Colors.red),
              _Stat('Daromad', "${formatMoney(revenue)}", Colors.orange),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _db
                    .collection('intercity_drivers')
                    .where('isActive', isEqualTo: true)
                    .snapshots(),
                builder: (_, dSnap) => _Stat(
                  'Faol haydovchilar',
                  '${dSnap.data?.docs.length ?? 0} ta',
                  Colors.teal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(Icons.bar_chart, color: color),
          ),
          title: Text(label),
          trailing: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      );
}
