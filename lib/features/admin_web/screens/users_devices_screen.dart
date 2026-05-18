import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersDevicesScreen extends StatelessWidget {
  const UsersDevicesScreen({super.key});

  static const _blue = Color(0xFF0D47A1);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _header(),
          const Material(
            color: Colors.white,
            child: TabBar(
              labelColor: _blue,
              unselectedLabelColor: Colors.black54,
              tabs: [
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
                Tab(icon: Icon(Icons.phonelink_lock), text: 'Қурилмалар'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _UsersTab(),
                _DevicesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.manage_accounts_outlined, color: _blue),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Фойдаланувчилар ва қурилмалар',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 3),
                Text(
                  'Телефон рақам, туғилган кун ва device binding маълумотлари',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _EmptyState(text: 'Фойдаланувчилар топилмади');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: docs.length,
          itemBuilder: (_, i) => _UserCard(doc: docs[i]),
        );
      },
    );
  }
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('device_bindings')
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _EmptyState(text: 'Қурилма binding маълумоти йўқ');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(18),
          itemCount: docs.length,
          itemBuilder: (_, i) => _DeviceCard(doc: docs[i]),
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final phone = _readString(d['phone']);
    final name = _readString(d['name']);
    final birthDate = _readString(d['birthDate']);
    final role =
        _readString(d['role']).isEmpty ? 'user' : _readString(d['role']);
    final gender = _readString(d['gender']);
    final updatedAt = _parseDate(d['updatedAt']);
    final createdAt = _parseDate(d['createdAt']);
    final address =
        _addressSummary(d['address'], _readString(d['legacyAddress']));

    return _InfoCard(
      icon: Icons.person_outline,
      title: name.isEmpty ? doc.id : name,
      chips: [
        _ChipData(role, _roleColor(role)),
        if (birthDate.isNotEmpty)
          _ChipData('Туғилган: $birthDate', Colors.pink),
      ],
      rows: [
        _InfoRow('User ID', doc.id),
        _InfoRow('Телефон', _dash(phone)),
        _InfoRow('Жинс', _dash(_genderLabel(gender))),
        _InfoRow('Манзил', _dash(address)),
        _InfoRow('Яратилган', _formatDateTime(createdAt)),
        _InfoRow('Янгиланган', _formatDateTime(updatedAt)),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final signals = _readMap(d['signals']);
    final status = _readString(d['status']);
    final userId = _readString(d['userId']);
    final phone = _readString(d['phone']);
    final signalKey = _readString(d['signalKey']);
    final updatedAt = _parseDate(d['updatedAt']);
    final lastSeenAt = _parseDate(d['lastSeenAt']);
    final createdAt = _parseDate(d['createdAt']);

    return _InfoCard(
      icon: Icons.phonelink_lock,
      title: doc.id,
      chips: [
        _ChipData(status.isEmpty ? 'active' : status, Colors.green),
        if (signals.isNotEmpty)
          _ChipData(_deviceSignalSummary(signals), Colors.blue),
      ],
      rows: [
        _InfoRow('User ID', _dash(userId)),
        _InfoRow('Телефон', _dash(phone)),
        _InfoRow('Signal key', _dash(signalKey)),
        _InfoRow('Device signals', _dash(_signalsLong(signals))),
        _InfoRow('Яратилган', _formatDateTime(createdAt)),
        _InfoRow('Охирги кўрилган', _formatDateTime(lastSeenAt)),
        _InfoRow('Янгиланган', _formatDateTime(updatedAt)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.rows,
    this.chips = const [],
  });

  final IconData icon;
  final String title;
  final List<_InfoRow> rows;
  final List<_ChipData> chips;

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE3F2FD),
              child: Icon(icon, color: const Color(0xFF0D47A1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: chip.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              chip.label,
                              style: TextStyle(
                                color: chip.color,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  for (final row in rows) _InfoLine(row: row),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.row});

  final _InfoRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              row.label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              row.value,
              style: const TextStyle(fontSize: 13, height: 1.25),
            ),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 52, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;
}

class _ChipData {
  const _ChipData(this.label, this.color);

  final String label;
  final Color color;
}

String _readString(dynamic value) => value?.toString().trim() ?? '';

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

DateTime? _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _dash(String value) => value.trim().isEmpty ? '—' : value.trim();

String _genderLabel(String value) {
  switch (value) {
    case 'male':
      return 'Эркак';
    case 'female':
      return 'Аёл';
    default:
      return value;
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'admin':
    case 'superadmin':
      return Colors.red;
    case 'driver':
      return Colors.deepPurple;
    case 'courier':
      return Colors.teal;
    default:
      return Colors.blueGrey;
  }
}

String _addressSummary(dynamic value, String legacy) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final parts = [
      _readString(map['district']),
      _readString(map['mfy']),
      _readString(map['street']),
      _readString(map['house']),
    ].where((v) => v.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
  }
  return legacy;
}

String _deviceSignalSummary(Map<String, dynamic> signals) {
  if (signals.isEmpty) return 'Device signal йўқ';
  final platform = _readString(signals['platform']);
  final brand = _readString(signals['brand']);
  final model = _readString(signals['model']);
  final browser = _readString(signals['browserName']);
  final os = _readString(signals['osVersion']);
  return [platform, brand, model, browser, os]
      .where((v) => v.isNotEmpty)
      .join(' • ');
}

String _signalsLong(Map<String, dynamic> signals) {
  if (signals.isEmpty) return '';
  final entries = signals.entries
      .map((e) => '${e.key}: ${_readString(e.value)}')
      .where((v) => !v.endsWith(': '))
      .toList();
  entries.sort();
  return entries.join('\n');
}
