import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

class CourierManagementScreen extends StatefulWidget {
  const CourierManagementScreen({super.key});
  @override
  State<CourierManagementScreen> createState() =>
      _CourierManagementScreenState();
}

class _CourierManagementScreenState extends State<CourierManagementScreen> {
  final _db = FirebaseFirestore.instance;
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _normalize(String raw) {
    final digits = phoneDigits(raw);
    if (digits.length == 9) return '998$digits';
    if (digits.length == 12 && digits.startsWith('998')) return digits;
    return digits;
  }

  Future<void> _addCourier() async {
    final id = _normalize(_phoneCtrl.text);
    final name = _nameCtrl.text.trim();
    if (id.length < 9) {
      setState(() => _error = 'Телефон рақамни тўлиқ киритинг');
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await _db.collection('couriers').doc(id).set({
        'phone': '+$id',
        'name': name.isEmpty ? 'Курьер' : name,
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _phoneCtrl.clear();
      _nameCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Курьер қўшилди: +$id'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Хатолик: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeCourier(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Text('Курьерни ўчириш'),
        content: Text('$name (+$id) ни ўчирасизми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ўчириш'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Aktiv reys borligini tekshirish
    final activeRoute = await _db
        .collection('delivery_routes')
        .where('courierId', isEqualTo: id)
        .where('status', whereIn: ['ready', 'active'])
        .limit(1)
        .get();

    if (activeRoute.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '❌ Kuryer aktiv reysda — avval reysni yakunlang'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _db.collection('couriers').doc(id).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Курьер ўчирилди')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add courier form
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '➕ Янги курьер қўшиш',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9 +\-]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Телефон рақам',
                            hintText: '+998 90 123 45 67',
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Исм (ихтиёрий)',
                            hintText: 'Курьер исми',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: _adding ? null : _addCourier,
                          icon: _adding
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: const Text('Қўшиш'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Couriers list
          const Text(
            'Рўйхатдаги курьерлар',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('couriers')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Хатолик: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delivery_dining,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Курьерлар йўқ',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final name = d['name'] as String? ?? 'Курьер';
                    final phone = d['phone'] as String? ?? '+$id';
                    final isOnline = d['isOnline'] as bool? ?? false;
                    final lat = (d['lat'] as num?)?.toDouble();
                    final lng = (d['lng'] as num?)?.toDouble();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOnline
                              ? Colors.green.shade100
                              : Colors.grey.shade100,
                          child: Icon(
                            Icons.delivery_dining,
                            color: isOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '$phone${isOnline ? ' · 🟢 Онлайн' : ' · ⚫ Офлайн'}'
                          '${lat != null ? '\n📍 ${lat.toStringAsFixed(4)}, ${lng?.toStringAsFixed(4)}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeCourier(id, name),
                          tooltip: 'Ўчириш',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
