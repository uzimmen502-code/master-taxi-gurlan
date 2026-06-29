import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';
import '../services/admin_role_service.dart';
import '../services/device_binding_admin_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/device_binding_repository.dart';

class UsersDevicesScreen extends StatefulWidget {
  const UsersDevicesScreen({super.key});

  @override
  State<UsersDevicesScreen> createState() => _UsersDevicesScreenState();
}

class _UsersDevicesScreenState extends State<UsersDevicesScreen> {
  static const _blue = AppColors.primary;
  static const _wideBreakpoint = 1000.0;

  late final PageController _pageCtrl;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideBreakpoint) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Expanded(child: _UsersColumnPanel()),
                      SizedBox(width: 10),
                      Expanded(child: _DevicesColumnPanel()),
                      SizedBox(width: 10),
                      Expanded(child: _MultiDeviceUsersColumnPanel()),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  _narrowColumnStrip(),
                  Expanded(
                    child: PageView(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _pageIndex = i),
                      children: [
                        SizedBox(
                          width: constraints.maxWidth,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(8, 8, 4, 8),
                            child: _UsersColumnPanel(),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                            child: _DevicesColumnPanel(),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(4, 8, 8, 8),
                            child: _MultiDeviceUsersColumnPanel(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _narrowColumnStrip() {
    const labels = [
      'Фойдаланувчилар',
      'Қурилмалар',
      'Кўп қурилмали',
    ];
    const icons = [
      Icons.people_alt_outlined,
      Icons.phonelink_lock,
      Icons.devices_other,
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final active = i == _pageIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              avatar: Icon(icons[i], size: 18, color: active ? _blue : null),
              label: Text(labels[i], style: const TextStyle(fontSize: 12)),
              selected: active,
              onSelected: (_) {
                setState(() => _pageIndex = i);
                _pageCtrl.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              },
              selectedColor: _blue.withValues(alpha: 0.15),
              checkmarkColor: _blue,
            ),
          );
        }),
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
                  'Фойдаланувчилар, қурилмалар ва бир рақамдан кўп қурилма',
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

class _UsersColumnPanel extends StatelessWidget {
  const _UsersColumnPanel();

  static const _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return _ListColumnShell(
      title: 'Фойдаланувчилар',
      icon: Icons.people_alt_outlined,
      accent: _accent,
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('updatedAt', descending: true)
          .limit(200)
          .snapshots(),
      emptyText: 'Фойдаланувчилар топилмади',
      itemBuilder: (_, doc) => _UserCard(doc: doc),
    );
  }
}

class _DevicesColumnPanel extends StatelessWidget {
  const _DevicesColumnPanel();

  static const _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _deviceBindingsStream(),
                  builder: (_, countSnap) {
                    final total =
                        _hashBindingDocs(countSnap.data?.docs).length;
                    return Row(
                      children: [
                        const Icon(Icons.phonelink_lock,
                            color: _accent, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Қурилмалар',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _accent,
                            ),
                          ),
                        ),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$total',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _accent,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                const _DeviceBindingAutoApproveToggle(),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _deviceBindingsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Хатолик: ${snap.error}'),
                    ),
                  );
                }
                final allDocs = snap.data?.docs ?? const [];
                final docs = _hashBindingDocs(allDocs);
                if (docs.isEmpty) {
                  final legacy = allDocs.length - docs.length;
                  return _EmptyState(
                    text: legacy > 0
                        ? 'Yangi format (64 hex) binding yo\'q\n'
                            'Eski format: $legacy ta — migrateOldBindings kerak'
                        : 'Qurilma binding yo\'q\n'
                            'Foydalanuvchi kod tasdiqlagach shu yerda chiqadi',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) =>
                      _DeviceBindingCard(doc: docs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceBindingAutoApproveToggle extends StatefulWidget {
  const _DeviceBindingAutoApproveToggle();

  @override
  State<_DeviceBindingAutoApproveToggle> createState() =>
      _DeviceBindingAutoApproveToggleState();
}

class _DeviceBindingAutoApproveToggleState
    extends State<_DeviceBindingAutoApproveToggle> {
  final _service = DeviceBindingAdminService();
  bool _busy = false;

  Future<void> _setEnabled(bool value) async {
    final adminPhone = _adminPhoneForCf(context);
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin telefon topilmadi — qayta kiring'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final err = await _service.setAutoApprove(
      adminPhone: adminPhone,
      enabled: value,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snap) {
        final enabled = snap.data?.data()?['deviceBindingAutoApprove'] == true;
        return Row(
          children: [
            Expanded(
              child: Text(
                enabled
                    ? 'Avtomatik tasdiqlash: YOQIQ'
                    : 'Avtomatik tasdiqlash: O\'CHIQ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled ? Colors.green.shade800 : Colors.black54,
                ),
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch.adaptive(
                value: enabled,
                activeThumbColor: AppColors.primary,
                onChanged: _setEnabled,
              ),
          ],
        );
      },
    );
  }
}

Stream<QuerySnapshot<Map<String, dynamic>>> _deviceBindingsStream() {
  return FirebaseFirestore.instance
      .collection('device_bindings')
      .limit(300)
      .snapshots();
}

/// Admin CF: `users/{docId}` bilan mos telefon.
String _adminPhoneForCf(BuildContext context) {
  final auth = context.read<AdminAuthService>();
  if (auth.phoneDigits != null && auth.phoneDigits!.isNotEmpty) {
    return auth.phoneDigits!;
  }
  final d = phoneDigits(auth.phone ?? '');
  return d.length >= 9 ? d : '';
}

/// Faqat yangi tizim: SHA-256 hash (64 hex) document ID.
List<QueryDocumentSnapshot<Map<String, dynamic>>> _hashBindingDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
) {
  if (docs == null) return const [];
  final list = docs
      .where((d) => DeviceBindingRepository.isValidFingerprintHash(d.id))
      .toList();
  list.sort((a, b) {
    final at = _parseDate(a.data()['updatedAt']) ??
        _parseDate(a.data()['lastSeenAt']) ??
        _parseDate(a.data()['firstRegisteredAt']);
    final bt = _parseDate(b.data()['updatedAt']) ??
        _parseDate(b.data()['lastSeenAt']) ??
        _parseDate(b.data()['firstRegisteredAt']);
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return list;
}

/// Бир `userId` орқали 2+ `device_bindings` бўлган фойдаланувчилар.
class _MultiDeviceUsersColumnPanel extends StatelessWidget {
  const _MultiDeviceUsersColumnPanel();

  static const _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final stream = _deviceBindingsStream();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (_, snap) {
                final groups =
                    _groupMultiDeviceUsers(_hashBindingDocs(snap.data?.docs));
                return Row(
                  children: [
                    const Icon(Icons.devices_other, color: _accent, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Кўп қурилмали',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _accent,
                        ),
                      ),
                    ),
                    if (snap.hasData)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${groups.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _accent,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Хатолик: ${snap.error}'),
                    ),
                  );
                }
                final groups =
                    _groupMultiDeviceUsers(_hashBindingDocs(snap.data?.docs));
                if (groups.isEmpty) {
                  return const _EmptyState(
                    text:
                        'Bir raqam orqali 2+ hash-binding yo\'q\n(so\'nggi 200 ichida)',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: groups.length,
                  itemBuilder: (_, i) => _MultiDeviceUserCard(group: groups[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiDeviceUserGroup {
  _MultiDeviceUserGroup({
    required this.userId,
    required this.phone,
    required this.devices,
  });

  final String userId;
  final String phone;
  final List<_BoundDeviceInfo> devices;

  int get deviceCount => devices.length;
}

class _BoundDeviceInfo {
  _BoundDeviceInfo({
    required this.deviceId,
    required this.phone,
    required this.status,
    required this.signalSummary,
    required this.lastSeenAt,
    required this.updatedAt,
  });

  final String deviceId;
  final String phone;
  final String status;
  final String signalSummary;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;
}

List<_MultiDeviceUserGroup> _groupMultiDeviceUsers(
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
) {
  if (docs == null || docs.isEmpty) return const [];

  final byUser = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final doc in docs) {
    final uid = _readString(doc.data()['userId']);
    if (uid.isEmpty) continue;
    byUser.putIfAbsent(uid, () => []).add(doc);
  }

  final groups = <_MultiDeviceUserGroup>[];
  for (final entry in byUser.entries) {
    if (entry.value.length < 2) continue;
    entry.value.sort((a, b) {
      final ad = _parseDate(a.data()['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _parseDate(b.data()['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    final devices = entry.value.map((doc) {
      final d = doc.data();
      final signals = _readMap(d['signals']);
      return _BoundDeviceInfo(
        deviceId: doc.id,
        phone: _readString(d['phone']),
        status: _readString(d['status']),
        signalSummary: _deviceSignalSummary(signals),
        lastSeenAt: _parseDate(d['lastSeenAt']),
        updatedAt: _parseDate(d['updatedAt']),
      );
    }).toList();
    final phone = devices
        .map((e) => e.phone)
        .firstWhere((p) => p.isNotEmpty, orElse: () => entry.key);
    groups.add(_MultiDeviceUserGroup(
      userId: entry.key,
      phone: phone,
      devices: devices,
    ));
  }

  groups.sort((a, b) {
    final byCount = b.deviceCount.compareTo(a.deviceCount);
    if (byCount != 0) return byCount;
    return a.userId.compareTo(b.userId);
  });
  return groups;
}

class _MultiDeviceUserCard extends StatelessWidget {
  const _MultiDeviceUserCard({required this.group});

  final _MultiDeviceUserGroup group;

  @override
  Widget build(BuildContext context) {
    final title =
        group.phone.isNotEmpty ? group.phone : group.userId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade800, size: 22),
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
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${group.deviceCount} та қурилма',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoLine(
              row: _InfoRow('User ID', group.userId),
            ),
            if (group.phone.isNotEmpty && group.phone != group.userId)
              _InfoLine(row: _InfoRow('Телефон', group.phone)),
            const SizedBox(height: 8),
            Text(
              'Қурилмалар:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < group.devices.length; i++) ...[
              _DeviceBindingLine(device: group.devices[i], index: i + 1),
              if (i < group.devices.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceBindingLine extends StatelessWidget {
  const _DeviceBindingLine({required this.device, required this.index});

  final _BoundDeviceInfo device;
  final int index;

  @override
  Widget build(BuildContext context) {
    final shortId = device.deviceId.length > 28
        ? '${device.deviceId.substring(0, 28)}…'
        : device.deviceId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. $shortId',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (device.signalSummary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              device.signalSummary,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Охирги: ${_formatDateTime(device.lastSeenAt)} • '
            '${device.status.isEmpty ? 'active' : device.status}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ListColumnShell extends StatelessWidget {
  const _ListColumnShell({
    required this.title,
    required this.icon,
    required this.accent,
    required this.stream,
    required this.emptyText,
    required this.itemBuilder,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String emptyText;
  final Widget Function(BuildContext, QueryDocumentSnapshot<Map<String, dynamic>>)
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (_, countSnap) {
                final total = countSnap.data?.docs.length;
                return Row(
                  children: [
                    Icon(icon, color: accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                    if (total != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$total',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Хатолик: ${snap.error}'),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return _EmptyState(text: emptyText);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) => itemBuilder(ctx, docs[i]),
                );
              },
            ),
          ),
        ],
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(
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
        ),
        if (role != 'superadmin')
          _UserRoleActions(
            userId: doc.id,
            phone: phone.isNotEmpty ? phone : doc.id,
            currentRole: role,
          ),
      ],
    );
  }
}

class _UserRoleActions extends StatefulWidget {
  const _UserRoleActions({
    required this.userId,
    required this.phone,
    required this.currentRole,
  });

  final String userId;
  final String phone;
  final String currentRole;

  @override
  State<_UserRoleActions> createState() => _UserRoleActionsState();
}

class _UserRoleActionsState extends State<_UserRoleActions> {
  final _roleService = AdminRoleService();
  bool _busy = false;

  static const Map<String, String> _roleLabels = {
    'admin': 'Admin',
    'finance': 'Finance',
    'auditor': 'Auditor',
    'user': 'Oddiy',
  };

  Future<void> _setRole(String role) async {
    final auth = context.read<AdminAuthService>();
    final adminPhone = auth.phone ?? '';
    if (adminPhone.isEmpty) return;

    final label = _roleLabels[role] ?? role;
    final isRemove = role == 'user';
    final title = isRemove ? 'Rolni olib tashlash' : '$label roli';
    final body = isRemove
        ? '${widget.phone} dan rol olib tashlanib, oddiy '
            'foydalanuvchi qilinsinmi?'
        : '${widget.phone} рақамига $label roli berilsinmi?';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isRemove ? 'Olib tashlash' : 'Berish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final err = await _roleService.setUserRole(
      adminPhone: adminPhone,
      targetPhone: widget.phone,
      role: role,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: err == null ? AppColors.primary : Colors.red,
        content: Text(
          err ??
              (isRemove
                  ? '✅ Rol olib tashlandi: ${widget.phone}'
                  : '✅ $label roli berildi: ${widget.phone}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.currentRole;

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _roleBtn('admin', Icons.admin_panel_settings, AppColors.primary, role),
          _roleBtn('finance', Icons.account_balance, Colors.teal, role),
          _roleBtn('auditor', Icons.fact_check, Colors.indigo, role),
          if (role != 'user')
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _setRole('user'),
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: const Text('Rolni olib tashlash',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
              ),
            ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _roleBtn(String role, IconData icon, Color color, String current) {
    final active = current == role;
    final label = _roleLabels[role] ?? role;
    return OutlinedButton.icon(
      onPressed: _busy || active ? null : () => _setRole(role),
      icon: Icon(icon, size: 18),
      label: Text(active ? '$label ✓' : label,
          style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: active ? color.withValues(alpha: 0.08) : null,
        side: BorderSide(color: color.withValues(alpha: active ? 0.9 : 0.5)),
      ),
    );
  }
}

class _DeviceBindingCard extends StatefulWidget {
  const _DeviceBindingCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_DeviceBindingCard> createState() => _DeviceBindingCardState();
}

class _DeviceBindingCardState extends State<_DeviceBindingCard> {
  final _service = DeviceBindingAdminService();
  bool _busy = false;

  QueryDocumentSnapshot<Map<String, dynamic>> get doc => widget.doc;

  Future<void> _run(Future<String?> Function() action, String okMsg) async {
    if (_busy) return;
    final adminPhone = _adminPhoneForCf(context);
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin telefon topilmadi — paneldan chiqib qayta kiring'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? okMsg),
        backgroundColor: err == null ? AppColors.button : Colors.red,
        duration: Duration(seconds: err == null ? 2 : 5),
      ),
    );
  }

  Future<void> _autoApprove() async {
    final adminPhone = _adminPhoneForCf(context);
    final phone = _readString(doc.data()['phone']);
    await _run(
      () => _service.autoApprove(
        adminPhone: adminPhone,
        deviceFingerprintHash: doc.id,
        phone: phone.isNotEmpty ? phone : null,
      ),
      'Avtomatik tasdiqlandi',
    );
  }

  Future<void> _manualApprove() async {
    final adminPhone = _adminPhoneForCf(context);
    final ctrl = TextEditingController(text: _readString(doc.data()['phone']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Qo\'lda tasdiqlash'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Telefon raqami (998...)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tasdiqlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => _service.manualApprove(
        adminPhone: adminPhone,
        deviceFingerprintHash: doc.id,
        phone: ctrl.text.trim(),
      ),
      'Qo\'lda tasdiqlandi',
    );
    ctrl.dispose();
  }

  Future<void> _unblock() async {
    final adminPhone = _adminPhoneForCf(context);
    await _run(
      () => _service.unblock(
        adminPhone: adminPhone,
        deviceFingerprintHash: doc.id,
      ),
      'Blok ochildi',
    );
  }

  Future<void> _reject() async {
    final adminPhone = _adminPhoneForCf(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rad etish'),
        content: const Text(
          'Bu qurilma binding o\'chirilsinmi? Foydalanuvchi qayta SMS bilan bog\'lanishi kerak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rad etish'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _run(
      () => _service.reject(
        adminPhone: adminPhone,
        deviceFingerprintHash: doc.id,
      ),
      'Binding rad etildi',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final signals = _readMap(d['signals']);
    final fingerprint = _readMap(d['fingerprint']);
    final phone = _readString(d['phone']);
    final verifiedMethod = _readString(d['verifiedMethod']);
    final isBlocked = d['isBlocked'] == true;
    final failedAttempts = (d['failedAttempts'] as num?)?.toInt() ?? 0;
    final updatedAt = _parseDate(d['updatedAt']);
    final lastSeenAt = _parseDate(d['lastSeenAt']);
    final createdAt = _parseDate(d['createdAt']);

    return _InfoCard(
      icon: Icons.phonelink_lock,
      title: '${doc.id.substring(0, 12)}…',
      chips: [
        if (isBlocked)
          const _ChipData('BLOKLANGAN', Colors.red)
        else
          const _ChipData('active', Colors.green),
        if (verifiedMethod.isNotEmpty)
          _ChipData(verifiedMethod, Colors.deepPurple),
        if (failedAttempts > 0)
          _ChipData('Urinish: $failedAttempts', Colors.orange),
      ],
      rows: [
        _InfoRow('Hash', doc.id),
        _InfoRow('Телефон', _dash(phone)),
        _InfoRow('Usul', _dash(verifiedMethod)),
        if (fingerprint.isNotEmpty)
          _InfoRow('Fingerprint', _dash(_fingerprintSummary(fingerprint)))
        else if (signals.isNotEmpty)
          _InfoRow('Device signals', _dash(_signalsLong(signals))),
        _InfoRow('Яaratilgan', _formatDateTime(createdAt)),
        _InfoRow('Охирги кўрилган', _formatDateTime(lastSeenAt)),
        _InfoRow('Яangilangan', _formatDateTime(updatedAt)),
      ],
      footerActions: _busy
          ? const [
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            ]
          : [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _autoApprove,
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text('Avtomatik tasdiqlash'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _manualApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Qo\'lda tasdiqlash'),
                  ),
                  if (isBlocked || failedAttempts > 0)
                    OutlinedButton.icon(
                      onPressed: _unblock,
                      icon: const Icon(Icons.lock_open, size: 16),
                      label: const Text('Blokni ochish'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _reject,
                    icon: const Icon(Icons.close, size: 16),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    label: const Text('Rad etish'),
                  ),
                ],
              ),
            ],
    );
  }

  String _fingerprintSummary(Map<String, dynamic> fp) {
    final brand = fp['brand']?.toString() ?? '';
    final model = fp['model']?.toString() ?? '';
    final platform = fp['platform']?.toString() ?? '';
    return [platform, brand, model].where((v) => v.isNotEmpty).join(' · ');
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.rows,
    this.chips = const [],
    this.footerActions = const [],
  });

  final IconData icon;
  final String title;
  final List<_InfoRow> rows;
  final List<_ChipData> chips;
  final List<Widget> footerActions;

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
              child: Icon(icon, color: AppColors.primary),
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
                  if (footerActions.isNotEmpty) ...footerActions,
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
