import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';
import 'chat_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  static const _blue   = Color(0xFF1565C0);
  static const _green  = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);
  static const _red    = Color(0xFFB71C1C);

  late TabController _tabCtrl;
  final _db = FirebaseFirestore.instance;

  String _orderFilter = 'all';
  StreamSubscription<QuerySnapshot>? _ordersSub;
  StreamSubscription<QuerySnapshot>? _driversSub;
  StreamSubscription<QuerySnapshot>? _tripsSub;
  StreamSubscription<QuerySnapshot>? _requestsSub;

  List<Map<String, dynamic>> _orders  = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _trips   = [];

  int _newCount       = 0;
  int _acceptedCount  = 0;
  int _readyCount     = 0;
  int _deliveredCount = 0;
  int _onlineDrivers  = 0;
  int _activeTrips    = 0;

  int _pendingRequests = 0;
  List<Map<String, dynamic>> _driverRequests = [];

  Map<String, dynamic> _prices = {};
  bool _pricesLoading = true;

  List<Map<String, dynamic>> _customProducts = [];
  bool _productsLoading = true;

  List<Map<String, dynamic>> _extraProducts = [];
  bool _extraProductsLoading = true;

  final Map<String, TextEditingController> _priceCtrlMap = {};
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _checkAdmin();
  }

  @override
  void dispose() {
    for (final c in _priceCtrlMap.values) {
      c.dispose();
    }
    _tabCtrl.dispose();
    _ordersSub?.cancel();
    _driversSub?.cancel();
    _tripsSub?.cancel();
    _requestsSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final prefs   = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('is_admin') ?? true;
    if (!isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    if (mounted) setState(() => _isAdmin = true);
    _listenOrders();
    _listenDrivers();
    _listenTrips();
    _listenDriverRequests();
    _loadPrices();
    _loadCustomProducts();
    _loadExtraProducts();
  }

  // ══════════════════════════════════════
  // НАРХЛАР
  // ══════════════════════════════════════
  Future<void> _loadPrices() async {
    try {
      final doc = await _db.collection('settings').doc('prices').get();
      if (doc.exists) {
        setState(() { _prices = doc.data()!; _pricesLoading = false; });
      } else {
        final defaults = {
          'flour_price':    8000,
          'milk_price':     7000,
          'kunjut_price':   30000,
          'semechka_price': 60000,
          'oil_price':      25000,
          'yupqa_price':    1500,
          'chorak_price':   2000,
          'toy_kichik':     3000,
          'toy_ortacha':    5000,
          'toy_katta':      8000,
          'taxi_base_price': 5000,
          'taxi_coefficient': 2000,
        };
        await _db.collection('settings').doc('prices').set(defaults);
        setState(() { _prices = defaults; _pricesLoading = false; });
      }
      // Controller'ларни яратиш
      _prices.forEach((key, val) {
        _priceCtrlMap[key] ??= TextEditingController(text: val.toString());
      });
    } catch (_) {
      setState(() => _pricesLoading = false);
    }
  }

  Future<void> _savePrice(String key, int value) async {
    try {
      await _db.collection('settings').doc('prices')
          .set({key: value}, SetOptions(merge: true));
      setState(() => _prices[key] = value);
      _showSnack('✅ Нарх сақланди', _green);
    } catch (_) {
      _showSnack('❌ Хатолик', _red);
    }
  }

  // ══════════════════════════════════════
  // STREAMЛАР
  // ══════════════════════════════════════
  void _listenOrders() {
    _ordersSub = _db.collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':           d.id,
          'type':         data['type']         ?? 'bread',
          'userName':     data['userName']     ?? '',
          'userPhone':    data['userPhone']    ?? '',
          'address':      data['address']      ?? '',
          'phone':        data['phone']        ?? '',
          'items':        data['items']        ?? [],
          'extras':       data['extras']       ?? [],
          'total':        data['total']        ?? 0,
          'status':       data['status']       ?? 'new',
          'deliveryTime': data['deliveryTime'] ?? '',
          'rejectReason': data['rejectReason'] ?? '',
          'createdAt':    data['createdAt'],
        };
      }).toList();
      setState(() {
        _orders         = list;
        _newCount       = list.where((o) => o['status'] == 'new').length;
        _acceptedCount  = list.where((o) => o['status'] == 'accepted').length;
        _readyCount     = list.where((o) => o['status'] == 'ready').length;
        _deliveredCount = list.where((o) => o['status'] == 'delivered').length;
      });
    });
  }

  void _listenDrivers() {
    _driversSub = _db.collection('drivers').snapshots().listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':       d.id,
          'name':     data['name']     ?? '',
          'phone':    data['phone']    ?? '',
          'car':      data['car']      ?? '',
          'plate':    data['plate']    ?? '',
          'rating':   (data['rating']  ?? 5.0).toDouble(),
          'isOnline': data['isOnline'] ?? false,
          'taxiType': data['taxiType'] ?? 'alone',
        };
      }).toList();
      setState(() {
        _drivers       = list;
        _onlineDrivers = list.where((d) => d['isOnline'] == true).length;
      });
    });
  }

  void _listenTrips() {
    _tripsSub = _db.collection('trips')
        .where('status', whereIn: ['searching', 'accepted'])
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':         d.id,
          'from':       data['from']                  ?? '',
          'to':         data['to']                    ?? '',
          'userPhone':  data['userPhone']             ?? '',
          'status':     data['status']                ?? 'searching',
          'taxiType':   data['taxiType']              ?? 'alone',
          'driverName': data['acceptedDriverName']    ?? '',
          'createdAt':  data['createdAt'],
        };
      }).toList();
      setState(() {
        _trips       = list;
        _activeTrips = list.length;
      });
    });
  }

  void _listenDriverRequests() {
    _requestsSub = _db
        .collection('driver_requests')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':        d.id,
          'name':      data['name']      ?? '',
          'phone':     data['phone']     ?? '',
          'car':       data['car']       ?? '',
          'plate':     data['plate']     ?? '',
          'taxiType':  data['taxiType']  ?? 'alone',
          'status':    data['status']    ?? 'pending',
          'createdAt': data['createdAt'],
        };
      }).toList();
      setState(() {
        _driverRequests  = list;
        _pendingRequests = list
            .where((r) => r['status'] == 'pending')
            .length;
      });
    });
  }

  Future<void> _approveDriver(Map<String, dynamic> req) async {
    try {
      final uid = (req['phone'] as String)
          .replaceAll(RegExp(r'[^\d]'), '');

      await _db.collection('drivers').doc(uid).set({
        'name':      req['name'],
        'phone':     req['phone'],
        'car':       req['car'],
        'plate':     req['plate'],
        'taxiType':  req['taxiType'],
        'isOnline':  false,
        'rating':    0.0,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db.collection('driver_requests')
          .doc(req['id'])
          .update({'status': 'approved'});

      _showSnack('✅ ${req['name']} тасдиқланди', _green);
    } catch (e) {
      _showSnack('❌ Хатолик: $e', _red);
    }
  }

  Future<void> _rejectDriver(Map<String, dynamic> req) async {
    try {
      await _db.collection('driver_requests')
          .doc(req['id'])
          .update({'status': 'rejected'});
      _showSnack('❌ ${req['name']} рад этилди', _red);
    } catch (e) {
      _showSnack('❌ Хатолик: $e', _red);
    }
  }

  // ══════════════════════════════════════
  // БУЮРТМА АМАЛЛАРИ
  // ══════════════════════════════════════
  void _showAcceptDialog(Map<String, dynamic> order) {
    final timeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: _green, size: 24),
          SizedBox(width: 8),
          Text('Қабул қилиш'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${order['userName'].isNotEmpty ? order['userName'] : order['userPhone']} буюртмасини қабул қилмоқчимисиз?',
            style: const TextStyle(fontSize: AppText.bodyMedium),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: timeCtrl,
            decoration: InputDecoration(
              hintText: 'Масалан: 14:30',
              labelText: '🕐 Тахминий вақт',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _green, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Вақт киритилмаса "Яқин орада" деб кетади',
              style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Бекор', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _acceptOrder(order['id'], timeCtrl.text.trim(), order['userPhone']);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('ҚАБУЛ'),
          ),
        ],
      ),
    ).then((_) => timeCtrl.dispose());
  }

  void _showRejectDialog(Map<String, dynamic> order) {
    String selectedReason = '';
    final reasons = [
      '😔 Хом ашё тугаган', '⏰ Бугун банд',
      '📍 Манзил узоқ', '🔢 Миқдор кўп', '✏️ Бошқа сабаб',
    ];
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.cancel, color: _red, size: 24),
            SizedBox(width: 8),
            Text('Рад этиш'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Сабабни танланг:',
                  style: TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ...reasons.map((r) => GestureDetector(
                onTap: () => setS(() => selectedReason = r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedReason == r ? _red.withOpacity(0.1) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selectedReason == r ? _red : Colors.grey.shade200),
                  ),
                  child: Text(r, style: TextStyle(
                      fontSize: AppText.bodyMedium,
                      fontWeight: selectedReason == r ? FontWeight.bold : FontWeight.normal,
                      color: selectedReason == r ? _red : Colors.black87)),
                ),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Бекор', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: selectedReason.isEmpty ? null : () async {
                Navigator.pop(context);
                await _rejectOrder(order['id'], selectedReason, order['userPhone']);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('РАД ЭТИШ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptOrder(String id, String time, String userPhone) async {
    try {
      final deliveryTime = time.isNotEmpty ? time : 'Яқин орада';
      final orderRef = _db.collection('orders').doc(id);
      final snap = await orderRef.get();
      if (!snap.exists) {
        _showSnack('❌ Буюртма топилмади', _red);
        return;
      }
      final data = snap.data()!;
      final wasNew = (data['status'] as String?) == 'new';

      final batch = _db.batch();
      batch.update(orderRef, {
        'status': 'accepted',
        'deliveryTime': deliveryTime,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // Нон буюртмаси: қўшимча маҳсулотлар (firestoreId) — қабулда soldToday += count
      // Қолдиқ: totalStock - soldToday (мас. 500 кг − 2 кг = 498 кг)
      if (wasNew && (data['type'] as String?) == 'bread') {
        final extras = data['extras'];
        if (extras is List) {
          for (final e in extras) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final fid = m['firestoreId'];
            if (fid is! String || fid.isEmpty) continue;
            final qty = (m['count'] as num?)?.toInt() ?? 0;
            if (qty <= 0) continue;
            batch.update(
              _db.collection('extra_products').doc(fid),
              {'soldToday': FieldValue.increment(qty)},
            );
          }
        }
      }

      await batch.commit();
      await _sendNotificationToUser(userPhone,
          '✅ Буюртмангиз қабул қилинди!', 'Тахминий вақт: $deliveryTime');
      _showSnack('✅ Қабул қилинди — $deliveryTime', _green);
    } catch (_) { _showSnack('❌ Хатолик', _red); }
  }

  String _digits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

  int? _extraRemainingFromOrder(Map<String, dynamic> e) {
    final fid = e['firestoreId'] as String?;
    Map<String, dynamic>? p;
    if (fid != null && fid.isNotEmpty) {
      p = _extraProducts.cast<Map<String, dynamic>?>().firstWhere(
            (x) => x?['id'] == fid,
            orElse: () => null,
          );
    }
    p ??= _extraProducts.cast<Map<String, dynamic>?>().firstWhere(
          (x) =>
              (x?['name']?.toString() ?? '') == (e['name']?.toString() ?? '') &&
              (x?['unit']?.toString() ?? '') == (e['unit']?.toString() ?? ''),
          orElse: () => null,
        );
    if (p == null) return null;
    final total = (p['totalStock'] ?? 0) as int;
    final sold = (p['soldToday'] ?? 0) as int;
    if (total <= 0) return null;
    return total - sold;
  }

  void _openSupportChat(String userPhone) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          targetPhone: _digits(userPhone),
          isAdmin: true,
        ),
      ),
    );
  }

  Future<void> _rejectOrder(String id, String reason, String userPhone) async {
    try {
      await _db.collection('orders').doc(id).update({
        'status': 'rejected', 'rejectReason': reason,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      await _sendNotificationToUser(userPhone, '❌ Буюртмангиз рад этилди', reason);
      _showSnack('Рад этилди: $reason', _red);
    } catch (_) { _showSnack('❌ Хатолик', _red); }
  }

  Future<void> _updateOrderStatus(String id, String status,
      {String userPhone = ''}) async {
    try {
      await _db.collection('orders').doc(id).update({'status': status});
      if (userPhone.isNotEmpty && (status == 'ready' || status == 'delivered')) {
        final title = status == 'ready'
            ? '🟠 Буюртмангиз тайёр!'
            : '🟢 Буюртма етказилди!';
        final body = status == 'ready'
            ? 'Яқин орада жўнатамиз'
            : 'Раҳмат!';
        await _sendNotificationToUser(userPhone, title, body);
      }
      _showSnack('Статус: ${_statusLabel(status)}', _statusColor(status));
    } catch (_) {}
  }

  Future<void> _sendNotificationToUser(
      String phone, String title, String body) async {
    try {
      final uid     = phone.replaceAll(RegExp(r'[^\d]'), '');
      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists) return;
      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;
      await _db.collection('notifications').add({
        'token': token, 'title': title, 'body': body,
        'targetPhone': phone, 'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ══════════════════════════════════════
  // ҲАЙДОВЧИ БОШҚАРУВИ
  // ══════════════════════════════════════
  Future<void> _deleteDriver(String id, String name) async {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Ҳайдовчини ўчириш'),
      content: Text('"$name" ни ўчиришни хоҳлайсизми?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Бекор', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await _db.collection('drivers').doc(id).delete();
              _showSnack('✅ $name ўчирилди', _green);
            } catch (_) {
              _showSnack('❌ Хатолик', _red);
            }
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: _red, foregroundColor: Colors.white),
          child: const Text('ЎЧИРИШ'),
        ),
      ],
    ));
  }

  void _showAddDriverDialog() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final carCtrl   = TextEditingController();
    final plateCtrl = TextEditingController();
    String taxiType = 'alone';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('+ Янги ҳайдовчи',
                      style: TextStyle(
                          fontSize: AppText.titleMedium,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _dialogField(nameCtrl,  '👤 Исм Фамилия',   TextInputType.name),
                  const SizedBox(height: 10),
                  _dialogField(phoneCtrl, '📞 Телефон рақами', TextInputType.phone),
                  const SizedBox(height: 10),
                  _dialogField(carCtrl,   '🚗 Машина маркаси', TextInputType.text),
                  const SizedBox(height: 10),
                  _dialogField(plateCtrl, '🔢 Давлат рақами',  TextInputType.text),
                  const SizedBox(height: 14),
                  const Text('Такси тури:',
                      style: TextStyle(
                          fontSize: AppText.bodySmall,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _taxiTypeBtn(setS, taxiType, 'alone',
                        '🚕 Маҳаллий', (v) => taxiType = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _taxiTypeBtn(setS, taxiType, 'marshrut',
                        '🚐 Маршрут', (v) => taxiType = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _taxiTypeBtn(setS, taxiType, 'intercity',
                        '🚌 Шаҳарлараро', (v) => taxiType = v)),
                  ]),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final name  = nameCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      final car   = carCtrl.text.trim();
                      final plate = plateCtrl.text.trim();
                      if (name.isEmpty)  { _showSnack('Исмни киритинг', _red); return; }
                      if (phone.isEmpty) { _showSnack('Телефонни киритинг', _red); return; }
                      if (car.isEmpty)   { _showSnack('Машинани киритинг', _red); return; }
                      if (plate.isEmpty) { _showSnack('Рақамни киритинг', _red); return; }
                      try {
                        final uid = phone.replaceAll(RegExp(r'[^\d]'), '');
                        await _db.collection('drivers').doc(uid).set({
                          'name':      name,
                          'phone':     phone,
                          'car':       car,
                          'plate':     plate,
                          'taxiType':  taxiType,
                          'isOnline':  false,
                          'rating':    0.0,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        Navigator.pop(ctx);
                        _showSnack('✅ $name қўшилди', _green);
                      } catch (e) {
                        _showSnack('❌ Хатолик: $e', _red);
                      }
                    },
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('ҚЎШИШ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint,
      TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _blue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _taxiTypeBtn(StateSetter setS, String current, String value,
      String label, ValueChanged<String> onChange) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => setS(() => onChange(value)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel ? _blue : Colors.grey.shade300),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: AppText.labelTiny,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.black87)),
      ),
    );
  }

  // ══════════════════════════════════════
  // ЁРДАМЧИ
  // ══════════════════════════════════════
  String _statusLabel(String s) {
    switch (s) {
      case 'new':       return '🔵 Янги';
      case 'accepted':  return '🟡 Қабул';
      case 'ready':     return '🟠 Тайёр';
      case 'delivered': return '🟢 Етказилди';
      case 'rejected':  return '🔴 Рад';
      default:          return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'new':       return Colors.blue;
      case 'accepted':  return Colors.orange;
      case 'ready':     return Colors.deepOrange;
      case 'delivered': return _green;
      case 'rejected':  return _red;
      default:          return Colors.grey;
    }
  }

  String _nextStatus(String s) {
    switch (s) {
      case 'accepted': return 'ready';
      case 'ready':    return 'delivered';
      default:         return s;
    }
  }

  String _nextStatusLabel(String s) {
    switch (s) {
      case 'accepted': return 'Тайёр';
      case 'ready':    return 'Етказилди ✅';
      default:         return '';
    }
  }

  String _fmtPrice(int p) {
    final s = p.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '';
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} '
          '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    return '';
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_orderFilter == 'all') return _orders;
    return _orders.where((o) => o['status'] == _orderFilter).toList();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ══════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════
  @override
  Widget build(BuildContext context) {

    // ✅ Admin текширилмагунича loading
    if (!_isAdmin) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Админ панели'),
        backgroundColor: _blue, foregroundColor: Colors.white, elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white, labelColor: Colors.white,
          unselectedLabelColor: Colors.white60, isScrollable: true,
          tabs: [
            Tab(text: 'Буюртмалар ($_newCount)'),
            Tab(text: 'Сафарлар ($_activeTrips)'),
            Tab(text: 'Ҳайдовчилар ($_onlineDrivers)'),
            Tab(text: 'Сўровлар ($_pendingRequests)'),
            const Tab(text: '💰 Нархлар'),
          ],
        ),
      ),
      body: Column(children: [
        _buildStats(),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildOrdersTab(),
            _buildTripsTab(),
            _buildDriversTab(),
            _buildRequestsTab(),
            _buildPricesTab(),
          ],
        )),
      ]),
    );
  }

  Widget _buildStats() {
    return Container(
      color: _blue,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(children: [
        _statItem('🔵', '$_newCount',       'Янги'),
        _statItem('🟡', '$_acceptedCount',  'Қабул'),
        _statItem('🟠', '$_readyCount',     'Тайёр'),
        _statItem('🟢', '$_deliveredCount', 'Етказилди'),
      ]),
    );
  }

  Widget _statItem(String emoji, String count, String label) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: AppText.bodyLarge)),
        Text(count, style: const TextStyle(
            fontSize: AppText.titleMedium, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: AppText.labelTiny, color: Colors.white70)),
      ]),
    ),
  );

  // ══════════════════════════════════════
  // БУЮРТМАЛАР ТАБ
  // ══════════════════════════════════════
  Widget _buildOrdersTab() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('all',       '📋 Барчаси'),
            _filterChip('new',       '🔵 Янги'),
            _filterChip('accepted',  '🟡 Қабул'),
            _filterChip('ready',     '🟠 Тайёр'),
            _filterChip('delivered', '🟢 Етказилди'),
            _filterChip('rejected',  '🔴 Рад'),
          ]),
        ),
      ),
      Expanded(
        child: _filteredOrders.isEmpty
            ? _emptyWidget('Буюртмалар йўқ')
            : ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: _filteredOrders.length,
            itemBuilder: (_, i) => _orderCard(_filteredOrders[i])),
      ),
    ]);
  }

  Widget _filterChip(String filter, String label) {
    final sel = _orderFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _orderFilter = filter),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _blue : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
            fontSize: AppText.bodySmall, fontWeight: FontWeight.w600,
            color: sel ? Colors.white : Colors.black87)),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status       = order['status'] as String;
    final isFood       = order['type'] == 'food';
    final items        = order['items']  as List;
    final extras       = order['extras'] as List;
    final total        = order['total']  as int;
    final isNew        = status == 'new';
    final isRejected   = status == 'rejected';
    final deliveryTime = order['deliveryTime'] as String;
    final rejectReason = order['rejectReason'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: _statusColor(status), width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(isFood ? '🍽️' : '🫓',
                style: const TextStyle(fontSize: AppText.titleLarge)),
            const SizedBox(width: 6),
            Text(isFood ? 'Овқат' : 'Нон',
                style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text(_fmtDate(order['createdAt']),
                style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade400)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_statusLabel(status), style: TextStyle(
                  fontSize: AppText.labelTiny, fontWeight: FontWeight.w600,
                  color: _statusColor(status))),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text(order['userName'].isNotEmpty ? order['userName'] : order['userPhone'],
                style: const TextStyle(fontSize: AppText.bodySmall)),
            const SizedBox(width: 8),
            const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
            const SizedBox(width: 2),
            Expanded(child: Text(order['address'],
                style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade500),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          ...items.take(2).map((item) {
            final name  = item['name']  as String? ?? '';
            final count = item['count'] as int?    ?? 1;
            return Text('• $name × $count',
                style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade600));
          }),
          ...extras.take(2).map((e) {
            final name = e['name'] as String? ?? '';
            final qty  = e['qty'];
            final unit = e['unit'] as String? ?? '';
            final remaining = e is Map<String, dynamic>
                ? _extraRemainingFromOrder(e)
                : null;
            return Text(
              '+ $name${qty != null ? " ($qty$unit)" : ""}'
              '${remaining != null ? "  |  омбор: $remaining $unit" : ""}',
              style: const TextStyle(fontSize: AppText.labelSmall, color: _green),
            );
          }),
          const SizedBox(height: 6),
          if (deliveryTime.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('🕐 $deliveryTime', style: const TextStyle(
                  fontSize: AppText.labelSmall, color: _green, fontWeight: FontWeight.w600)),
            ),
          if (rejectReason.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(rejectReason, style: TextStyle(
                  fontSize: AppText.labelSmall, color: _red, fontWeight: FontWeight.w600)),
            ),
          if (deliveryTime.isNotEmpty || rejectReason.isNotEmpty) const SizedBox(height: 6),
          Row(children: [
            Text(_fmtPrice(total), style: TextStyle(
                fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold,
                color: isFood ? _green : _orange)),
            const Text(' сўм', style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey)),
            const Spacer(),
            GestureDetector(
              onTap: () => _openSupportChat(order['userPhone'] as String? ?? ''),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _blue.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 14, color: _blue),
                    SizedBox(width: 4),
                    Text('Чат', style: TextStyle(
                      fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (isNew) ...[
              GestureDetector(
                onTap: () => _showRejectDialog(order),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _red.withOpacity(0.3))),
                  child: const Text('РАД', style: TextStyle(
                      fontSize: AppText.labelSmall, fontWeight: FontWeight.bold, color: _red)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showAcceptDialog(order),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
                  child: const Text('ҚАБУЛ', style: TextStyle(
                      fontSize: AppText.labelSmall, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
            if (!isNew && !isRejected && status != 'delivered')
              ElevatedButton(
                onPressed: () => _updateOrderStatus(order['id'], _nextStatus(status),
                    userPhone: order['userPhone']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _statusColor(_nextStatus(status)),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(
                      fontSize: AppText.labelSmall, fontWeight: FontWeight.bold),
                ),
                child: Text(_nextStatusLabel(status)),
              ),
          ]),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════
  // САФАРЛАР ТАБ
  // ══════════════════════════════════════
  Widget _buildTripsTab() {
    return _trips.isEmpty
        ? _emptyWidget('Фаол сафарлар йўқ')
        : ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _trips.length,
        itemBuilder: (_, i) => _tripCard(_trips[i]));
  }

  Widget _tripCard(Map<String, dynamic> trip) {
    final status     = trip['status'] as String;
    final isAccepted = status == 'accepted';
    final color      = isAccepted ? _green : _blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(trip['taxiType'] == 'marshrut' ? '🚐' : '🚕',
              style: const TextStyle(fontSize: AppText.titleLarge)),
          const SizedBox(width: 6),
          Text(trip['taxiType'] == 'marshrut' ? 'Маршрут' : 'Алоҳида',
              style: const TextStyle(fontSize: AppText.bodySmall, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isAccepted ? '🟢 Қабул' : '🔵 Қидирилмоқда',
                style: TextStyle(fontSize: AppText.labelTiny, color: color,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.circle, size: 8, color: Colors.green),
          const SizedBox(width: 6),
          Expanded(child: Text(trip['from'],
              style: const TextStyle(fontSize: AppText.bodySmall))),
        ]),
        if ((trip['to'] as String).isNotEmpty) ...[
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on, size: 8, color: Colors.red),
            const SizedBox(width: 6),
            Expanded(child: Text(trip['to'],
                style: const TextStyle(fontSize: AppText.bodySmall))),
          ]),
        ],
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.phone_outlined, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Text(trip['userPhone'],
              style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
          const Spacer(),
          Text(_fmtDate(trip['createdAt']),
              style: TextStyle(fontSize: AppText.labelTiny, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════
  // ҲАЙДОВЧИЛАР ТАБ
  // ══════════════════════════════════════
  Widget _buildDriversTab() {
    return Stack(children: [
      _drivers.isEmpty
          ? _emptyWidget('Ҳайдовчилар йўқ')
          : ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
          itemCount: _drivers.length,
          itemBuilder: (_, i) => _driverCard(_drivers[i])),
      Positioned(
        bottom: 16, right: 16,
        child: FloatingActionButton.extended(
          onPressed: () => _showAddDriverDialog(),
          backgroundColor: _blue,
          icon: const Icon(Icons.person_add, color: Colors.white),
          label: const Text('Ҳайдовчи қўшиш',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }

  Widget _driverCard(Map<String, dynamic> d) {
    final isOnline = d['isOnline'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(
            color: isOnline ? _green : Colors.grey.shade300, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: isOnline ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
          child: Text(d['name'].isNotEmpty ? d['name'][0] : '?',
              style: TextStyle(fontSize: AppText.titleMedium, fontWeight: FontWeight.bold,
                  color: isOnline ? _green : Colors.grey)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['name'], style: const TextStyle(
              fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
          Row(children: [
            const Icon(Icons.directions_car, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text('${d['car']} · ${d['plate']}',
                style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
          ]),
          Row(children: [
            const Icon(Icons.star, size: 12, color: Colors.amber),
            const SizedBox(width: 2),
            Text('${d['rating']}',
                style: const TextStyle(fontSize: AppText.labelSmall, color: Colors.amber)),
            const SizedBox(width: 8),
            Text(d['phone'],
                style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
          ]),
        ])),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: isOnline ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8)),
            child: Text(isOnline ? '🟢 Онлайн' : '⚫ Офлайн',
                style: TextStyle(fontSize: AppText.labelTiny,
                    fontWeight: FontWeight.w600,
                    color: isOnline ? _green : Colors.grey)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _deleteDriver(d['id'], d['name']),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Ўчириш',
                  style: TextStyle(fontSize: AppText.labelTiny,
                      fontWeight: FontWeight.w600, color: _red)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════
  // ҲАЙДОВЧИ СЎРОВЛАРИ ТАБ
  // ══════════════════════════════════════
  Widget _buildRequestsTab() {
    final pending  = _driverRequests
        .where((r) => r['status'] == 'pending').toList();
    final approved = _driverRequests
        .where((r) => r['status'] == 'approved').toList();
    final rejected = _driverRequests
        .where((r) => r['status'] == 'rejected').toList();

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Container(
          color: Colors.white,
          child: TabBar(
            labelColor: _blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _blue,
            tabs: [
              Tab(text: '⏳ Янги (${pending.length})'),
              Tab(text: '✅ Тасдиқ (${approved.length})'),
              Tab(text: '❌ Рад (${rejected.length})'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _requestsList(pending,  showActions: true),
          _requestsList(approved, showActions: false),
          _requestsList(rejected, showActions: false),
        ])),
      ]),
    );
  }

  Widget _requestsList(
      List<Map<String, dynamic>> list,
      {required bool showActions}) {
    if (list.isEmpty) return _emptyWidget('Сўровлар йўқ');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: list.length,
      itemBuilder: (_, i) => _requestCard(list[i], showActions),
    );
  }

  Widget _requestCard(Map<String, dynamic> req, bool showActions) {
    final status   = req['status'] as String;
    final taxiType = req['taxiType'] as String;

    final taxiLabel = taxiType == 'marshrut'
        ? '🚐 Маршрут'
        : taxiType == 'intercity'
        ? '🚌 Шаҳарлараро'
        : '🚕 Маҳаллий';

    final statusColor = status == 'approved'
        ? _green
        : status == 'rejected'
        ? _red
        : _blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(color: statusColor, width: 4)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: statusColor.withOpacity(0.1),
              child: Text(
                (req['name'] as String).isNotEmpty
                    ? (req['name'] as String)[0]
                    : '?',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req['name'],
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Text(req['phone'],
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(taxiLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.directions_car,
                size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text('${req['car']} · ${req['plate']}',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600)),
            const Spacer(),
            Text(_fmtDate(req['createdAt']),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400)),
          ]),
          if (showActions) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectDriver(req),
                  icon: const Icon(Icons.close,
                      size: 16, color: _red),
                  label: const Text('РАД',
                      style: TextStyle(color: _red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveDriver(req),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('ТАСДИҚЛАШ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  // МАҲСУЛОТЛАР
  // ══════════════════════════════════════
  Future<void> _loadCustomProducts() async {
    try {
      final snap = await _db.collection('bread_products')
          .orderBy('createdAt', descending: false).get();
      setState(() {
        _customProducts = snap.docs.map((d) {
          final data = d.data();
          return {'id': d.id, ...data};
        }).toList();
        _productsLoading = false;
      });
    } catch (_) {
      setState(() => _productsLoading = false);
    }
  }

  Future<void> _loadExtraProducts() async {
    try {
      final snap = await _db.collection('extra_products')
          .orderBy('createdAt', descending: false).get();
      setState(() {
        _extraProducts = snap.docs.map((d) {
          return {'id': d.id, ...d.data()};
        }).toList();
        _extraProductsLoading = false;
      });
    } catch (_) {
      setState(() => _extraProductsLoading = false);
    }
  }

  void _showAddExtraProductDialog({Map<String, dynamic>? existing}) {
    final nameCtrl  = TextEditingController(text: existing?['name']  ?? '');
    final qtyCtrl   = TextEditingController(text: existing?['qty']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final bonusThresholdCtrl = TextEditingController(text: existing?['bonusThreshold']?.toString() ?? '');
    final bonusQtyCtrl = TextEditingController(text: existing?['bonusQty']?.toString() ?? '');
    final bonusPercentCtrl = TextEditingController(text: existing?['bonusPercent']?.toString() ?? '');
    String pickedImagePath = existing?['imageBase64'] ?? '';
    String unit = existing?['unit'] ?? 'kg';
    bool bonusEnabled = (existing?['bonusEnabled'] ?? false) as bool;
    final stockCtrl = TextEditingController(text: existing?['totalStock']?.toString() ?? ''); // ← YANGI
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existing != null ? 'Маҳсулотни таҳрирлаш' : '+ Янги маҳсулот',
                      style: const TextStyle(
                          fontSize: AppText.titleMedium, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // Номи
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Маҳсулот номи',
                      hintText: 'Масалан: Кунжут дони',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _blue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Миқдор + бирлик
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Миқдори',
                          hintText: '500',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _blue, width: 1.5)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: unit,
                            items: const [
                              DropdownMenuItem(value: 'kg',   child: Text('кг')),
                              DropdownMenuItem(value: 'dona', child: Text('дона')),
                            ],
                            onChanged: (v) => setS(() => unit = v ?? 'kg'),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Нарх
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Нархи (сўм)',
                      suffixText: 'сўм',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _blue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ✅ YANGI: Jami miqdor
                  const SizedBox(height: 12),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Жами миқдори (${unit == 'kg' ? 'кг' : 'дона'})',
                      hintText: 'Масалан: 500',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: bonusEnabled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('🎁 Бонус таклиф ёқилсин'),
                    subtitle: const Text('Миқдор ошса чегирма/бепул таклиф'),
                    onChanged: (v) => setS(() => bonusEnabled = v),
                  ),
                  if (bonusEnabled) ...[
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: bonusThresholdCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'Порог (${unit == 'kg' ? 'кг' : 'дона'})',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: bonusQtyCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'Бонус миқдори',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bonusPercentCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Чегирма фоизи (50 ёки 100)',
                        suffixText: '%',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Расм галерея
                  // Расм галерея
                  if (pickedImagePath.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        base64Decode(pickedImagePath),
                        height: 120, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 48, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final file = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 30,
                          maxWidth: 400,
                          maxHeight: 400);
                      if (file != null) {
                        final bytes = await file.readAsBytes();

                        if (bytes.length > 800000) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ Расм жуда катта. Кичроқ расм танланг.'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        final b64 = base64Encode(bytes);
                        setS(() => pickedImagePath = b64);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Расм юкланди (${(bytes.length / 1024).round()} кб)'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.photo_library),
                    label: Text(pickedImagePath.isEmpty
                        ? '📷 Расм танлаш' : '📷 Расмни ўзгартириш'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _blue,
                        side: const BorderSide(color: _blue)),
                  ),
                  const SizedBox(height: 16),

                  // Тугмалар
                  Row(children: [
                    if (existing != null)
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          await _db.collection('extra_products')
                              .doc(existing['id']).delete();
                          Navigator.pop(ctx);
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (mounted) _loadExtraProducts();
                        },
                        icon: const Icon(Icons.delete, color: _red, size: 16),
                        label: const Text('Ўчириш', style: TextStyle(color: _red)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      )),
                    if (existing != null) const SizedBox(width: 8),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () async {
                        final name  = nameCtrl.text.trim();
                        final qty   = double.tryParse(
                            qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                        final price = int.tryParse(
                            priceCtrl.text.trim().replaceAll(' ', '')) ?? 0;
                        if (name.isEmpty) {
                          _showSnack('Номни киритинг', _red); return;
                        }
                        if (qty <= 0) {
                          _showSnack('Миқдорни киритинг', _red); return;
                        }
                        if (price <= 0) {
                          _showSnack('Нархни киритинг', _red); return;
                        }
                        final data = {
                          'name': name, 'qty': qty, 'unit': unit,
                          'price': price,
                          'totalStock': int.tryParse(stockCtrl.text.trim()) ?? 0, // ← YANGI
                          'soldToday': existing?['soldToday'] ?? 0,               // ← YANGI
                          'bonusEnabled': bonusEnabled,
                          'bonusThreshold': int.tryParse(bonusThresholdCtrl.text.trim()) ?? 0,
                          'bonusQty': int.tryParse(bonusQtyCtrl.text.trim()) ?? 0,
                          'bonusPercent': int.tryParse(bonusPercentCtrl.text.trim()) ?? 0,
                          'imageBase64': pickedImagePath,
                        };
                        try {
                          if (existing != null) {
                            await _db.collection('extra_products')
                                .doc(existing['id']).update(data);
                          } else {
                            await _db.collection('extra_products').add({
                              ...data, 'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          Navigator.pop(ctx);
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (mounted) {
                            _loadExtraProducts();
                            _showSnack('✅ Сақланди', _green);
                          }
                        } catch (e) {
                          _showSnack('❌ Хатолик: $e', _red);
                        }
                      },
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Сақлаш'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddProductDialog({Map<String, dynamic>? existing}) {
    final nameCtrl  = TextEditingController(text: existing?['name']  ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final emojiCtrl = TextEditingController(text: existing?['emoji'] ?? '🫓');
    String type = existing?['type'] ?? 'tayyor';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setS) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existing != null ? 'Маҳсулотни таҳрирлаш' : 'Янги маҳсулот',
                      style: const TextStyle(
                          fontSize: AppText.titleMedium, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _typeBtn(setS, type, 'yopish', '🔥 Ёпиш',  (v) => type = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _typeBtn(setS, type, 'tayyor', '✅ Тайёр', (v) => type = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _typeBtn(setS, type, 'toy',    '💍 Тўй',   (v) => type = v)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Маҳсулот номи',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _blue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Нарх (сўм/дона)', suffixText: 'сўм',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _blue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emojiCtrl,
                    decoration: InputDecoration(
                      labelText: 'Эмодзи (1 та)', hintText: '🍞',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _blue, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    if (existing != null)
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          await _db.collection('bread_products')
                              .doc(existing['id']).delete();
                          Navigator.pop(ctx);
                          await _loadCustomProducts();
                        },
                        icon: const Icon(Icons.delete, color: _red, size: 16),
                        label: const Text('Ўчириш', style: TextStyle(color: _red)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      )),
                    if (existing != null) const SizedBox(width: 8),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () async {
                        final name  = nameCtrl.text.trim();
                        final price = int.tryParse(
                            priceCtrl.text.trim().replaceAll(' ', '')) ?? 0;
                        if (name.isEmpty) { _showSnack('Номни киритинг', _red); return; }
                        if (price <= 0)   { _showSnack('Нархни киритинг', _red); return; }
                        final data = {
                          'name': name, 'price': price, 'type': type,
                          'emoji': emojiCtrl.text.trim().isNotEmpty
                              ? emojiCtrl.text.trim() : '🫓',
                        };
                        try {
                          if (existing != null) {
                            await _db.collection('bread_products')
                                .doc(existing['id']).update(data);
                          } else {
                            await _db.collection('bread_products').add({
                              ...data, 'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          Navigator.pop(ctx);
                          if (mounted) {
                            await _loadCustomProducts();
                            _showSnack('✅ Сақланди', _green);
                          }
                        } catch (e) {
                          _showSnack('❌ Хатолик: $e', _red);
                        }
                      },
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Сақлаш'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeBtn(StateSetter setS, String current, String value,
      String label, ValueChanged<String> onChange) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => setS(() => onChange(value)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? _blue : Colors.grey.shade300),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.labelSmall, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.black87)),
      ),
    );
  }

  // ══════════════════════════════════════
  // НАРХЛАР ТАБ
  // ══════════════════════════════════════
  Widget _buildPricesTab() {
    if (_pricesLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _priceSection('🌾 Хом ашё нархлари', [
          _priceItem('Ун нархи (сўм/кг)',    'flour_price',
              (_prices['flour_price']    ?? 8000)  as int),
          _priceItem('Сут нархи (сўм/л)',    'milk_price',
              (_prices['milk_price']     ?? 7000)  as int),
          _priceItem('Кунжут (сўм/кг)',      'kunjut_price',
              (_prices['kunjut_price']   ?? 30000) as int),
          _priceItem('Семечка (сўм/кг)',     'semechka_price',
              (_prices['semechka_price'] ?? 60000) as int),
          _priceItem('Ўсимлик ёғи (сўм/л)', 'oil_price',
              (_prices['oil_price']      ?? 25000) as int),
        ]),
        const SizedBox(height: 16),
        _priceSection('🫓 Ёпиш ҳақи (сўм/дона)', [
          _priceItem('Юпқа нон', 'yupqa_price',
              (_prices['yupqa_price'] ?? 1500) as int),
          _priceItem('Чўрак',    'chorak_price',
              (_prices['chorak_price'] ?? 2000) as int),
        ]),
        const SizedBox(height: 16),
        _priceSection('💍 Тўй нони (сўм/дона)', [
          _priceItem('Кичик',  'toy_kichik',
              (_prices['toy_kichik']  ?? 3000) as int),
          _priceItem('Ўртача', 'toy_ortacha',
              (_prices['toy_ortacha'] ?? 5000) as int),
          _priceItem('Катта',  'toy_katta',
              (_prices['toy_katta']   ?? 8000) as int),
        ]),
        const SizedBox(height: 16),
        _priceSection('🚕 Такси нархлари', [
          _priceItem('Бошланғич нарх (сўм)', 'taxi_base_price',
              (_prices['taxi_base_price'] ?? 5000) as int),
          _priceItem('Коэффициент (сўм/км)', 'taxi_coefficient',
              (_prices['taxi_coefficient'] ?? 2000) as int),
        ]),
        const SizedBox(height: 16),

        // Нон маҳсулотлари
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _orange.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Text('🫓 Нон маҳсулотлари',
                    style: TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showAddProductDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.add, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Қўшиш', style: TextStyle(
                          fontSize: AppText.labelSmall, color: Colors.white,
                          fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ]),
            ),
            if (_productsLoading)
              const Padding(padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: _blue))
            else if (_customProducts.isEmpty)
              Padding(padding: const EdgeInsets.all(16),
                  child: Text('Ҳозирча маҳсулот йўқ — қўшинг!',
                      style: TextStyle(fontSize: AppText.bodyMedium, color: Colors.grey.shade400),
                      textAlign: TextAlign.center))
            else
              ..._customProducts.map((p) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: Text(
                    p['type'] == 'yopish' ? '🔥' : p['type'] == 'toy' ? '💍' : '✅',
                    style: const TextStyle(fontSize: 20)),
                title: Text(p['name'] ?? '',
                    style: const TextStyle(
                        fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
                subtitle: Text('${p['price'] ?? 0} сўм/дона',
                    style: TextStyle(
                        fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: _blue, size: 18),
                  onPressed: () => _showAddProductDialog(existing: p),
                ),
              )),
          ]),
        ),
        const SizedBox(height: 16),

        // Қўшимча маҳсулотлар
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Text('🛒 Қўшимча маҳсулотлар',
                    style: TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showAddExtraProductDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.add, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Қўшиш', style: TextStyle(
                          fontSize: AppText.labelSmall, color: Colors.white,
                          fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ]),
            ),
            if (_extraProductsLoading)
              const Padding(padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: _blue))
            else if (_extraProducts.isEmpty)
              Padding(padding: const EdgeInsets.all(16),
                  child: Text('Маҳсулот қўшинг',
                      style: TextStyle(fontSize: AppText.bodyMedium, color: Colors.grey.shade400),
                      textAlign: TextAlign.center))
            else
              ..._extraProducts.map((p) {
                final unit = p['unit'] == 'kg' ? 'кг' : 'дона';
                final qty  = p['qty'];
                final b64  = p['imageBase64'] as String? ?? '';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: b64.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(b64),
                      width: 40, height: 40, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                      const Icon(Icons.shopping_basket, size: 32, color: Colors.grey),
                    ),
                  )
                      : const Icon(Icons.shopping_basket, size: 32, color: Colors.grey),
                  title: Text(p['name'] ?? '',
                      style: const TextStyle(
                          fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '$qty $unit — ${_fmtPrice((p['price'] ?? 0) as int)} сўм'
                        '\n📦 ${p['totalStock'] ?? 0} та | ✅ ${p['soldToday'] ?? 0} сотилди',
                    style: TextStyle(
                        fontSize: AppText.labelSmall, color: Colors.grey.shade500),
                  ),
                );
              }),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _priceSection(String title, List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Text(title, style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
          ]),
        ),
        ...items,
      ]),
    );
  }

  Widget _priceItem(String label, String key, int currentValue) {
    final ctrl = _priceCtrlMap[key] ??= TextEditingController(
        text: currentValue.toString());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: AppText.bodyMedium))),
        SizedBox(
          width: 100,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _blue, width: 1.5)),
              suffixText: 'сўм',
              suffixStyle: TextStyle(
                  fontSize: AppText.labelTiny, color: Colors.grey.shade400),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            final val = int.tryParse(ctrl.text) ?? currentValue;
            _savePrice(key, val);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.save, color: Colors.white, size: 16),
          ),
        ),
      ]),
    );
  }

  Widget _emptyWidget(String msg) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
    const SizedBox(height: 12),
    Text(msg, style: TextStyle(fontSize: AppText.bodyLarge, color: Colors.grey.shade400)),
  ],
  ));
}