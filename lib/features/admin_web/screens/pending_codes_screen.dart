import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Firestore `settings/app` maydoni.
const String kPendingCodeAutoGenerate = 'pendingCodeAutoGenerate';

/// 6 xonali kod yaratib `pending_codes` ni approved qiladi.
Future<void> approvePendingCodeDoc(
  String docId, {
  Map<String, dynamic>? data,
}) async {
  final rawPhone = (data?['phone'] ?? docId).toString();
  final id = phoneDigits(rawPhone.isNotEmpty ? rawPhone : docId);
  if (id.length < 12) return;

  final code = (100000 + Random().nextInt(900000)).toString();
  await FirebaseFirestore.instance.collection('pending_codes').doc(id).set({
    'phone': '+$id',
    'code': code,
    'status': 'approved',
    'approvedAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 5)),
    ),
  }, SetOptions(merge: true));
}

Future<void> setPendingCodeAutoGenerate(bool enabled) async {
  await FirebaseFirestore.instance.collection('settings').doc('app').set({
    kPendingCodeAutoGenerate: enabled,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Stream<bool> watchPendingCodeAutoGenerate() {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('app')
      .snapshots()
      .map((s) => s.data()?[kPendingCodeAutoGenerate] == true);
}

/// Admin panel ochiq turganida avtomatik kod yaratish (barcha бўлимларда).
class PendingCodeAutoListener {
  PendingCodeAutoListener();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingSub;
  bool _enabled = false;
  final Set<String> _inFlight = {};

  void start() {
    _settingsSub?.cancel();
    _pendingSub?.cancel();
    _settingsSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .snapshots()
        .listen((snap) {
      _enabled = snap.data()?[kPendingCodeAutoGenerate] == true;
    });
    _pendingSub = FirebaseFirestore.instance
        .collection('pending_codes')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(_onPending);
  }

  Future<void> _onPending(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (!_enabled) return;
    for (final doc in snap.docs) {
      if (_inFlight.contains(doc.id)) continue;
      final data = doc.data();
      final code = (data['code'] as String?)?.trim();
      if (code != null && code.length == 6) continue;

      _inFlight.add(doc.id);
      try {
        await approvePendingCodeDoc(doc.id, data: data);
      } finally {
        _inFlight.remove(doc.id);
      }
    }
  }

  void dispose() {
    _settingsSub?.cancel();
    _pendingSub?.cancel();
    _inFlight.clear();
  }
}

/// Avtomatik / қўлда режим — sidebar ва экранда.
class PendingCodeAutoModeSwitch extends StatefulWidget {
  const PendingCodeAutoModeSwitch({
    super.key,
    this.onLightBackground = false,
    this.compact = false,
  });

  final bool onLightBackground;
  final bool compact;

  @override
  State<PendingCodeAutoModeSwitch> createState() =>
      _PendingCodeAutoModeSwitchState();
}

class _PendingCodeAutoModeSwitchState extends State<PendingCodeAutoModeSwitch> {
  bool _busy = false;

  Future<void> _setEnabled(bool value) async {
    setState(() => _busy = true);
    try {
      await setPendingCodeAutoGenerate(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        widget.onLightBackground ? Colors.black87 : Colors.white;
    final subColor =
        widget.onLightBackground ? Colors.black54 : Colors.white70;

    return StreamBuilder<bool>(
      stream: watchPendingCodeAutoGenerate(),
      builder: (context, snap) {
        final enabled = snap.data == true;
        return Row(
          mainAxisSize: widget.compact ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Автомат код',
                    style: TextStyle(
                      fontSize: widget.compact ? 11 : 13,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  if (!widget.compact)
                    Text(
                      enabled
                          ? 'Янги сўровларга код автоматик'
                          : '«Код яратиш» қўлда',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                ],
              ),
            ),
            if (_busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.onLightBackground
                      ? AppColors.primary
                      : Colors.white,
                ),
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

/// Admin panel: telefon uchun 6 xonali kod yaratish (fake SMS).
class PendingCodesScreen extends StatefulWidget {
  const PendingCodesScreen({super.key});

  @override
  State<PendingCodesScreen> createState() => _PendingCodesScreenState();
}

class _PendingCodesScreenState extends State<PendingCodesScreen> {
  static const _blue = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Expanded(
          child: StreamBuilder<bool>(
            stream: watchPendingCodeAutoGenerate(),
            builder: (context, autoSnap) {
              final autoOn = autoSnap.data == true;
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('pending_codes')
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Хатолик: ${snapshot.error}'));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        autoOn
                            ? 'Фаол сўровлар йўқ (автомат режим ёқиқ)'
                            : 'Фаол код сўровлари йўқ',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                    );
                  }
                  docs.sort((a, b) {
                    final at = a.data()['createdAt'] as Timestamp?;
                    final bt = b.data()['createdAt'] as Timestamp?;
                    return (bt ?? Timestamp(0, 0))
                        .compareTo(at ?? Timestamp(0, 0));
                  });
                  return ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: docs.length,
                    itemBuilder: (_, i) => _PendingCodeCard(
                      doc: docs[i],
                      autoMode: autoOn,
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

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.pin_outlined, color: _blue),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Код сўровлари',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Фойдаланувчи телефон киритganda — админ код',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const PendingCodeAutoModeSwitch(onLightBackground: true),
        ],
      ),
    );
  }
}

class _PendingCodeCard extends StatefulWidget {
  const _PendingCodeCard({
    required this.doc,
    required this.autoMode,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool autoMode;

  @override
  State<_PendingCodeCard> createState() => _PendingCodeCardState();
}

class _PendingCodeCardState extends State<_PendingCodeCard> {
  bool _busy = false;

  Future<void> _generateAndApprove() async {
    setState(() => _busy = true);
    try {
      await approvePendingCodeDoc(widget.doc.id, data: widget.doc.data());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Код яратилди'),
            backgroundColor: AppColors.button,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final phone = (data['phone'] ?? '+${widget.doc.id}').toString();
    final createdAt = data['createdAt'] as Timestamp?;
    final hash = (data['deviceFingerprintHash'] ?? '').toString();
    final hashShort =
        hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;

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
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (createdAt != null)
                    Text(
                      'Сўров: ${createdAt.toDate()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  if (hashShort.isNotEmpty)
                    Text(
                      'Fingerprint: $hashShort',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  if (widget.autoMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Автомат режим — код тезда яратилади',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.autoMode)
              ElevatedButton.icon(
                onPressed: _busy ? null : _generateAndApprove,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.vpn_key_outlined, size: 18),
                label: const Text('Код яратиш'),
              )
            else if (_busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
