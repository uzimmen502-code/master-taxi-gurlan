import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/app_theme.dart';

class BreadScreen extends StatefulWidget {
  const BreadScreen({super.key});
  @override
  State<BreadScreen> createState() => _BreadScreenState();
}

class _BreadScreenState extends State<BreadScreen> {
  static const _primary = Color(0xFFE65100);
  static const _orange  = Color(0xFFFF8F00);

  final _db   = FirebaseFirestore.instance;
  final Map<int, int> _cart = {};

  int _kunjutCount   = 0;
  int _semechkaCount = 0;
  int _oilCount      = 0;
  int _sedanaCount   = 0;
  int _pendingCount  = 0;

  // ✅ 3-тузатиш: Қўшимча маҳсулотлар савати асосий экранда
  final Map<int, int> _extraProductsCart = {};

  Map<String, dynamic> _prices = {};
  bool _pricesLoading = true;

  List<Map<String, dynamic>> _extraProductsList = [];
  bool _extraProductsLoading = true;
  bool _showHistory = false;
  List<Map<String, dynamic>> _orderHistory = [];
  bool _historyLoading = false;
  bool _hasInternet = true;
  Map<String, dynamic>? _pendingOrder;
  StreamSubscription? _extraProductsSub;
  StreamSubscription? _productsSub;
  StreamSubscription? _connectSub;

  final List<Map<String, dynamic>> _staticYopish = [
    {
      'id': 1, 'name': 'Юпқа нон', 'type': 'ёпиш', 'priceKey': 'yupqa_price',
      'emoji': '🫓', 'image': 'assets/bread_yupqa.png',
      'desc': 'Юпқа, хрустли тандир нон',
      'flour_g': 300, 'milk_ratio': 0.575,
    },
    {
      'id': 2, 'name': 'Чўрак', 'type': 'ёпиш', 'priceKey': 'chorak_price',
      'emoji': '🫓', 'image': 'assets/bread_churak.png',
      'desc': 'Қалин, мўл тандир нон',
      'flour_g': 250, 'milk_ratio': 0.575,
    },
  ];

  List<Map<String, dynamic>> _firestoreProducts = [];
  bool _firestoreLoading = true;

  List<Map<String, dynamic>> get _toyNon => [
    {
      'id': 91, 'name': 'Тўй нон (кичик)', 'type': 'той',
      'priceKey': 'toy_kichik', 'emoji': '🫓',
      'image': 'assets/bread_toy.png', 'desc': '∅ 20 см',
      'flour_g': (_prices['toy_kichik_flour'] as num?)?.toInt() ?? 400,
      'milk_ml': (_prices['toy_kichik_milk']  as num?)?.toInt() ?? 200,
    },
    {
      'id': 92, 'name': 'Тўй нон (ўртача)', 'type': 'той',
      'priceKey': 'toy_ortacha', 'emoji': '🫓',
      'image': 'assets/bread_toy.png', 'desc': '∅ 30 см',
      'flour_g': (_prices['toy_ortacha_flour'] as num?)?.toInt() ?? 600,
      'milk_ml': (_prices['toy_ortacha_milk']  as num?)?.toInt() ?? 300,
    },
    {
      'id': 93, 'name': 'Тўй нон (катта)', 'type': 'той',
      'priceKey': 'toy_katta', 'emoji': '🫓',
      'image': 'assets/bread_toy.png', 'desc': '∅ 40 см',
      'flour_g': (_prices['toy_katta_flour'] as num?)?.toInt() ?? 900,
      'milk_ml': (_prices['toy_katta_milk']  as num?)?.toInt() ?? 450,
    },
  ];

  List<Map<String, dynamic>> get _allProducts =>
      [..._staticYopish, ..._firestoreProducts, ..._toyNon];

  int get _cartCount => _cart.values.fold(0, (sum, c) => sum + c);

  int _productPrice(Map<String, dynamic> p) {
    if (p.containsKey('price')) return p['price'] as int;
    final key = p['priceKey'] as String?;
    if (key != null && _prices.containsKey(key)) {
      return (_prices[key] as num).toInt();
    }
    return 1000;
  }

  @override
  void initState() {
    super.initState();
    _loadPrices();
    _listenFirestoreProducts();
    _listenExtraProducts();
    _checkConnectivity();
    _loadPendingOrder();
  }

  Future<void> _loadOrderHistory() async {
    setState(() => _historyLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) {
        setState(() => _historyLoading = false);
        return;
      }
      final snap = await _db
          .collection('orders')
          .where('userPhone', isEqualTo: phone)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      if (!mounted) return;
      setState(() {
        _orderHistory = snap.docs.map((d) {
          final data = d.data();
          return {
            'id':        d.id,
            'items':     data['items']    ?? [],
            'extras':    data['extras']   ?? [],
            'total':     data['total']    ?? 0,
            'status':    data['status']   ?? 'new',
            'address':   data['address']  ?? '',
            'createdAt': data['createdAt'],
          };
        }).toList();
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
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

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':  return const Color(0xFFFF8F00);
      case 'ready':     return Colors.deepOrange;
      case 'delivered': return const Color(0xFF2E7D32);
      case 'rejected':  return Colors.red;
      default:          return Colors.blue;
    }
  }

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

  @override
  void dispose() {
    _productsSub?.cancel();
    _extraProductsSub?.cancel();
    _connectSub?.cancel();
    super.dispose();
  }

  void _listenFirestoreProducts() {
    _productsSub = _db.collection('bread_products')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _firestoreProducts = snap.docs.map((d) {
          final data = d.data();
          return {
            'id':          d.id.hashCode,
            'firestoreId': d.id,
            'name':        data['name']     ?? '',
            'type':        _mapType(data['type'] ?? 'tayyor'),
            'price':       (data['price']   ?? 0) as int,
            'emoji':       data['emoji']    ?? '🫓',
            'imageUrl':    data['imageUrl'] ?? '',
            'image':       data['image']    ?? '',
            'desc':        data['name']     ?? '',
          };
        }).toList();
        _firestoreLoading = false;
      });
    });
  }

  void _listenExtraProducts() {
    _extraProductsSub = _db.collection('extra_products')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _extraProductsList = snap.docs.map((d) {
          return {
            'id': d.id.hashCode,
            'firestoreId': d.id,       // ✅ YANGI: Yangilash uchun kerak
            ...d.data()
          };
        }).toList();
        _extraProductsLoading = false;
      });
    });
  }

  String _mapType(String t) {
    switch (t) {
      case 'yopish': return 'ёпиш';
      case 'toy':    return 'той';
      default:       return 'тайёр';
    }
  }

  Future<void> _loadPrices() async {
    try {
      final doc = await _db.collection('settings').doc('prices').get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() { _prices = doc.data()!; _pricesLoading = false; });
      } else {
        setState(() { _pricesLoading = false; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _pricesLoading = false; });
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

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectivity(result);
    _connectSub = Connectivity()
        .onConnectivityChanged
        .listen(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final connected =
    results.any((r) => r != ConnectivityResult.none);
    if (mounted) {
      setState(() => _hasInternet = connected);
      if (connected && _pendingOrder != null) {
        _sendPendingOrder();
      }
    }
  }

  Future<void> _sendPendingOrder() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final pending = prefs.getString('pending_orders');
      if (pending == null) return;

      final list = jsonDecode(pending) as List;
      if (list.isEmpty) return;

      int sent = 0;
      for (final order in list) {
        try {
          final firestoreOrder = Map<String, dynamic>.from(
              order as Map<String, dynamic>);
          // ISO string → Timestamp
          if (firestoreOrder['createdAt'] is String) {
            firestoreOrder['createdAt'] = Timestamp.fromDate(
                DateTime.parse(
                    firestoreOrder['createdAt'] as String));
          }
          await _db.collection('orders').add(firestoreOrder);
          sent++;
        } catch (_) {}
      }

      await prefs.remove('pending_orders');
      if (!mounted) return;
      setState(() {
        _pendingOrder = null;
        _pendingCount = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $sent та кутилган буюртма юборилди!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {}
  }

  Future<void> _loadPendingOrder() async {
    final prefs   = await SharedPreferences.getInstance();
    final pending = prefs.getString('pending_orders');
    if (pending != null) {
      final list = jsonDecode(pending) as List;
      if (mounted) setState(() {
        _pendingCount = list.length;
        if (list.isNotEmpty) {
          _pendingOrder = list.first as Map<String, dynamic>;
        }
      });
    }
  }

  void _showCart() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('🛒 Сават бўш'),
        backgroundColor: _orange, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartSheet(
        cart: _cart,
        allProducts: _allProducts,
        prices: _prices,
        productPrice: _productPrice,
        fmtPrice: _fmtPrice,
        kunjutCount: _kunjutCount,
        semechkaCount: _semechkaCount,
        oilCount: _oilCount,
        sedanaCount: _sedanaCount,
        onKunjutChanged:   (v) => setState(() => _kunjutCount   = v),
        onSemechkaChanged: (v) => setState(() => _semechkaCount = v),
        onOilChanged:      (v) => setState(() => _oilCount      = v),
        onSedanaChanged:   (v) => setState(() => _sedanaCount   = v),
        extraProductsList: _extraProductsList,
        hasInternet: _hasInternet,
        onClose: () => Navigator.pop(context),
        onOrderSent: () {
          Navigator.pop(context);
          setState(() {
            _cart.clear();
            _extraProductsCart.clear();
            _kunjutCount = 0;
            _semechkaCount = 0;
            _oilCount = 0;
            _sedanaCount = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('✅ Буюртма юборилди! Тасдиқланса хабар берамиз.'),
            backgroundColor: _primary, behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        },
        // ✅ 3-тузатиш: Қўшимча маҳсулотлар саватини узатиш
        extraProductsCart: _extraProductsCart,
        onExtraCartChanged: (id, v) => setState(() {
          if (v <= 0) {
            _extraProductsCart.remove(id);
            _cart.remove(id);
          } else {
            _extraProductsCart[id] = v;
            _cart[id] = v;
          }
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      body: Stack(children: [
        (_pricesLoading || _firestoreLoading)
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true, expandedHeight: 130,
            backgroundColor: const Color(0xFFE65100),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('🫓 Нон буюртма',
                  style: TextStyle(fontSize: AppText.titleMedium,
                      fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF8F00)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () async {
                  setState(() => _showHistory = !_showHistory);
                  if (_showHistory && _orderHistory.isEmpty) {
                    await _loadOrderHistory();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _primary.withOpacity(0.3)),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6)],
                  ),
                  child: Row(children: [
                    const Icon(Icons.history,
                        color: Color(0xFFE65100), size: 20),
                    const SizedBox(width: 10),
                    const Text('📋 Буюртмалар тарихи',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Icon(
                      _showHistory
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey,
                    ),
                  ]),
                ),
              ),
            ),
          ),

          if (_showHistory)
            SliverToBoxAdapter(
              child: _historyLoading
                  ? const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFE65100))),
              )
                  : _orderHistory.isEmpty
                  ? Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('Буюртмалар тарихи йўқ',
                      style: TextStyle(
                          color: Colors.grey)),
                ),
              )
                  : Column(
                children: _orderHistory
                    .map((o) => _historyCard(o))
                    .toList(),
              ),
            ),
          _sectionHeader('🔥 Ёпиш хизмати'),
          _productGrid(_staticYopish),
          _sectionHeader('✅ Тайёр нонлар'),
          _productGrid(_firestoreProducts.where((p) => p['type'] == 'тайёр').toList()),
          _sectionHeader('💍 Тўй нони'),
          _productGrid(_toyNon),
          _sectionHeader('🛒 Қўшимча маҳсулотлар'),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  final p = _extraProductsList[i];
                  final count = _extraProductsCart[p['id'] as int] ?? 0;
                  return _extraProductCard(p, count);
                },
                childCount: _extraProductsList.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ]),
        if (!_hasInternet)
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8)],
                ),
                child: Row(children: [
                  const Icon(Icons.wifi_off,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '📵 Интернет йўқ — буюртма сақланиб юборилади',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_pendingCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$_pendingCount та кутмоқда',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ),
          ),
        if (_cartCount > 0)
          Positioned(
            bottom: 16, left: 16, right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: _showCart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFE65100), Color(0xFFFF8F00)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: _primary.withOpacity(0.4),
                        blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_cartSummaryText(),
                              style: const TextStyle(
                                  fontSize: AppText.bodyMedium, color: Colors.white70),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const Text('Саватни кўриш →',
                              style: TextStyle(
                                  fontSize: AppText.bodySmall, color: Colors.white60)),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('$_cartCount та',
                          style: const TextStyle(
                              fontSize: AppText.titleMedium,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  String _cartSummaryText() {
    final parts = <String>[];
    _cart.forEach((id, count) {
      final p = _allProducts.firstWhere((p) => p['id'] == id, orElse: () => {});
      if (p.isNotEmpty) parts.add('${p['name']} × $count');
    });
    return parts.join(', ');
  }

  SliverToBoxAdapter _sectionHeader(String title) =>
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Container(width: 4, height: 18,
              decoration: BoxDecoration(color: _orange,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(
              fontSize: AppText.titleSmall, fontWeight: FontWeight.bold)),
        ]),
      ));

  Widget _historyCard(Map<String, dynamic> order) {
    final status = order['status'] as String;
    final total  = order['total']  as int;
    final items  = order['items']  as List;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
            left: BorderSide(
                color: _statusColor(status), width: 4)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6)],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('🫓',
                  style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  items.take(2).map((i) =>
                  '${i['name']} × ${i['count']}').join(', '),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(status))),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.location_on_outlined,
                  size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order['address'] as String,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_fmtPrice(total)} сўм',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              _fmtDate(order['createdAt']),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400),
            ),
          ]),
    );
  }

  SliverPadding _productGrid(List<Map<String, dynamic>> items) =>
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 10,
              crossAxisSpacing: 10, childAspectRatio: 0.72),
          delegate: SliverChildBuilderDelegate(
                  (_, i) => _productCard(items[i]),
              childCount: items.length),
        ),
      );

  Widget _productCard(Map<String, dynamic> product) {
    final id       = product['id'] as int;
    final count    = _cart[id] ?? 0;
    final type     = product['type'] as String;
    final isYopish = type == 'ёпиш';
    final isToy    = type == 'той';
    final accentColor = isYopish ? _orange : _primary;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: (product['imageUrl'] != null && (product['imageUrl'] as String).isNotEmpty)
                  ? Image.network(product['imageUrl'] as String,
                  width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(product['emoji'] ?? '🫓',
                          style: const TextStyle(fontSize: 42))))
                  : (product['image'] != null && (product['image'] as String).isNotEmpty)
                  ? Image.asset(product['image'] as String,
                  width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(product['emoji'] ?? '🫓',
                          style: const TextStyle(fontSize: 42))))
                  : Center(child: Text(product['emoji'] ?? '🫓',
                  style: const TextStyle(fontSize: 42))),
            ),
          ),
          if (isToy)
            Positioned(top: 6, left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.purple.shade600,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      id == 91 ? 'Кичик' : id == 92 ? 'Ўртача' : 'Катта',
                      style: const TextStyle(
                          fontSize: AppText.labelTiny, color: Colors.white,
                          fontWeight: FontWeight.bold)),
                )),
        ])),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product['name'],
                style: const TextStyle(
                    fontSize: AppText.bodySmall, fontWeight: FontWeight.bold),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                isYopish ? 'Ёпиш хизмати' : isToy ? 'Тўй нони' : 'Тайёр',
                style: TextStyle(fontSize: AppText.labelTiny, color: accentColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
            if (!isYopish && !isToy) ...[
              const SizedBox(height: 2),
              Text('${_fmtPrice(_productPrice(product))} сўм',
                  style: TextStyle(fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.bold, color: accentColor)),
            ],
            const SizedBox(height: 6),
            count > 0
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (_cart[id]! > 1) _cart[id] = _cart[id]! - 1;
                  else _cart.remove(id);
                }),
                child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200)),
                    child: const Icon(Icons.remove, size: 14, color: Colors.red)),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$count', style: TextStyle(
                      fontSize: AppText.titleMedium,
                      fontWeight: FontWeight.bold, color: accentColor))),
              GestureDetector(
                onTap: () => setState(() => _cart[id] = (_cart[id] ?? 0) + 1),
                child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accentColor.withOpacity(0.3))),
                    child: Icon(Icons.add, size: 14, color: accentColor)),
              ),
            ])
                : SizedBox(
              width: double.infinity, height: 30,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _cart[id] = 1),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Қўшиш',
                    style: TextStyle(fontSize: AppText.labelSmall)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor, foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _extraProductCard(Map<String, dynamic> p, int count) {
    final id         = p['id'] as int;
    final price      = (p['price'] as num?)?.toInt() ?? 0;
    final unit       = p['unit'] == 'kg' ? 'кг' : 'дона';
    final qty        = p['qty'] ?? '';
    final totalStock = (p['totalStock'] ?? 0) as int;
    final soldToday  = (p['soldToday'] ?? 0) as int;
    final remaining  = totalStock > 0 ? totalStock - soldToday : 999;
    final isSoldOut  = totalStock > 0 && remaining <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
              color: isSoldOut ? Colors.grey.shade200 : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(
              isSoldOut ? '🚫' : '🛒',
              style: const TextStyle(fontSize: 24))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['name'] ?? '', style: const TextStyle(
              fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
          Text('$qty $unit · ${_fmtPrice(price)} сўм/дона',
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
          // Qolgan miqdor
          if (totalStock > 0)
            Text(
              remaining > 3
                  ? '📦 $remaining та қолди'
                  : remaining > 0
                  ? '⚠️ Охирги $remaining та!'
                  : '🔴 ТУГАДИ',
              style: TextStyle(
                fontSize: AppText.labelTiny,
                color: remaining > 3 ? Colors.green : remaining > 0 ? Colors.orange : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
        ])),

        // Tugagan — tugma yo'q
        if (isSoldOut)
          const SizedBox(width: 0)
        // Qo'shilgan — [✓ Qo'shildi]
        else if (count > 0)
          GestureDetector(
            onTap: _showCart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.check, size: 16, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Қўшилди',
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          )
        // Qo'shilmagan — [+ Qo'shish]
        else
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _extraProductsCart[id] = 1;
                _cart[id] = 1;
              }),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Қўшиш',
                  style: TextStyle(fontSize: AppText.labelSmall)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════
// САВАТ SHEET
// ══════════════════════════════════════
class _CartSheet extends StatefulWidget {
  final Map<int, int> cart;
  final List<Map<String, dynamic>> allProducts;
  final Map<String, dynamic> prices;
  final int Function(Map<String, dynamic>) productPrice;
  final String Function(int) fmtPrice;
  final VoidCallback onClose;
  final VoidCallback onOrderSent;
  final int kunjutCount;
  final int semechkaCount;
  final int oilCount;
  final int sedanaCount;
  final ValueChanged<int> onKunjutChanged;
  final ValueChanged<int> onSemechkaChanged;
  final ValueChanged<int> onOilChanged;
  final ValueChanged<int> onSedanaChanged;
  final List<Map<String, dynamic>> extraProductsList;
  final bool hasInternet;

  // ✅ 3-тузатиш: Янги параметрлар
  final Map<int, int> extraProductsCart;
  final void Function(int id, int val) onExtraCartChanged;

  const _CartSheet({
    required this.cart, required this.allProducts, required this.prices,
    required this.productPrice, required this.fmtPrice,
    required this.onClose, required this.onOrderSent,
    required this.kunjutCount, required this.semechkaCount, required this.oilCount,
    required this.sedanaCount,
    required this.onKunjutChanged, required this.onSemechkaChanged, required this.onOilChanged,
    required this.onSedanaChanged,
    required this.extraProductsList,
    required this.hasInternet,
    // ✅ 3-тузатиш: Конструкторда янги параметрлар
    required this.extraProductsCart,
    required this.onExtraCartChanged,
  });

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  static const _green  = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);

  final _db = FirebaseFirestore.instance;

  late int _kunjutCount;
  late int _semechkaCount;
  late int _oilCount;
  late int _sedanaCount;

  // ✅ 3-тузатиш: late қилиб ўзгартирилди
  late Map<int, int> _extraProductsCart;

  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl  = TextEditingController();

  Map<int, String> _flourMilkChoice = {};
  bool _isSending = false;

  List<Map<String, dynamic>> get _extraProductsList =>
      widget.extraProductsList;

  @override
  void initState() {
    super.initState();
    // ✅ 3-тузатиш: parent'дан маълумотни олиш
    _extraProductsCart = Map<int, int>.from(widget.extraProductsCart);

    _kunjutCount   = widget.kunjutCount;
    _semechkaCount = widget.semechkaCount;
    _oilCount      = widget.oilCount;
    _sedanaCount   = widget.sedanaCount;
    _loadProfile();
    for (final entry in widget.cart.entries) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == entry.key, orElse: () => {});
      if (p.isNotEmpty && (p['type'] == 'ёпиш' || p['type'] == 'той')) {
        _flourMilkChoice[entry.key] = 'ours';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text  = prefs.getString('user_name')    ?? '';
      _phoneCtrl.text = prefs.getString('user_phone')   ?? '';
      _addrCtrl.text  = prefs.getString('user_address') ?? '';
    });
  }

  int get _breadTotal {
    int total = 0;
    widget.cart.forEach((id, count) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == id, orElse: () => {});
      if (p.isEmpty) return;
      final type      = p['type'] as String;
      final basePrice = widget.productPrice(p) * count;
      if (type == 'ёпиш' || type == 'той') {
        final choice = _flourMilkChoice[id] ?? 'ours';
        total += choice == 'ours' ? basePrice + _flourMilkCost(p, count) : basePrice;
      } else {
        total += basePrice;
      }
    });
    return total;
  }

  int _flourMilkCost(Map<String, dynamic> p, int count) {
    final flourG     = (p['flour_g']    as num?)?.toInt() ?? 300;
    final milkMl     = (p['milk_ml']    as num?)?.toInt()
        ?? ((p['milk_ratio'] as num?)?.toDouble() ?? 0.575 * flourG).round();
    final flourPrice = (widget.prices['flour_price'] as num?)?.toInt() ?? 8000;
    final milkPrice  = (widget.prices['milk_price']  as num?)?.toInt() ?? 7000;
    return (flourG / 1000 * flourPrice * count).round() +
        (milkMl / 1000 * milkPrice * count).round();
  }

  int _oilCost() {
    int totalFlourG = 0;
    widget.cart.forEach((id, c) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == id, orElse: () => {});
      if (p.isNotEmpty && p['type'] == 'ёпиш') {
        totalFlourG += ((p['flour_g'] as num?)?.toInt() ?? 300) * c;
      }
    });
    final oP = (widget.prices['oil_price'] as num?)?.toInt() ?? 25000;
    return ((totalFlourG / 10000.0) * _oilCount * oP).round();
  }

  int get _extrasTotal {
    int total = 0;
    if (_yopishTotalCount > 0) {
      final kP = (widget.prices['kunjut_price']   as num?)?.toInt() ?? 30000;
      final sP = (widget.prices['semechka_price'] as num?)?.toInt() ?? 60000;
      final dP = (widget.prices['sedana_price']   as num?)?.toInt() ?? 50000;
      if (_kunjutCount   > 0) total += (2  / 1000 * kP * _kunjutCount).round();
      if (_semechkaCount > 0) total += (5  / 1000 * sP * _semechkaCount).round();
      if (_oilCount      > 0) total += _oilCost();
      if (_sedanaCount   > 0) total += (5  / 1000 * dP * _sedanaCount).round();
    }
    for (final p in _extraProductsList) {
      final id    = p['id'] as int;
      final count = _extraProductsCart[id] ?? 0;
      if (count > 0) {
        total += _extraLineTotal(p, count);
      }
    }
    return total;
  }

  int _extraDiscount(Map<String, dynamic> p, int count) {
    if (count <= 0) return 0;
    final enabled = (p['bonusEnabled'] ?? false) as bool;
    if (!enabled) return 0;
    final threshold = (p['bonusThreshold'] as num?)?.toInt() ?? 0;
    final bonusQty = (p['bonusQty'] as num?)?.toInt() ?? 0;
    final bonusPercent = (p['bonusPercent'] as num?)?.toInt() ?? 0;
    final price = (p['price'] as num?)?.toInt() ?? 0;
    if (threshold <= 0 || bonusQty <= 0 || bonusPercent <= 0 || price <= 0) {
      return 0;
    }
    if (count < threshold) return 0;
    final discountedUnits = bonusQty > count ? count : bonusQty;
    return (price * discountedUnits * (bonusPercent / 100)).round();
  }

  int _extraLineTotal(Map<String, dynamic> p, int count) {
    final price = (p['price'] as num?)?.toInt() ?? 0;
    final base = price * count;
    final discount = _extraDiscount(p, count);
    final total = base - discount;
    return total < 0 ? 0 : total;
  }

  int get _yopishTotalCount {
    int count = 0;
    widget.cart.forEach((id, c) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == id, orElse: () => {});
      if (p.isNotEmpty && p['type'] == 'ёпиш') count += c;
    });
    return count;
  }

  int get _saltYeastCost {
    int total = 0;
    widget.cart.forEach((id, c) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == id, orElse: () => {});
      if (p.isNotEmpty &&
          (p['type'] == 'ёпиш' || p['type'] == 'той')) {
        total += c;
      }
    });
    return total * 50;
  }

  int get _grandTotal => _breadTotal + _extrasTotal + _saltYeastCost;

  /// Firestore `totalStock`/`soldToday` бўйича қўшимча маҳсулот учун йўқори чек (йўқ бўлса 99).
  int _extraProductMaxQty(Map<String, dynamic> p) {
    final totalStock = (p['totalStock'] ?? 0) as int;
    if (totalStock <= 0) return 99;
    final sold = (p['soldToday'] ?? 0) as int;
    return (totalStock - sold).clamp(0, 99);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  Map<String, dynamic> _buildOrderData(
      String name, String phone, String addr) {
    final items = <Map<String, dynamic>>[];
    widget.cart.forEach((id, count) {
      final p = widget.allProducts.firstWhere(
              (p) => p['id'] == id, orElse: () => {});
      if (p.isEmpty) return;
      final type   = p['type'] as String;
      final choice = _flourMilkChoice[id] ?? 'yours';
      items.add({
        'id': id, 'name': p['name'],
        'count': count, 'type': type,
        'flourMilk': (type == 'ёпиш' || type == 'той')
            ? choice : 'none',
        'price': widget.productPrice(p),
      });
    });

    final extras = <Map<String, dynamic>>[];
    if (_kunjutCount > 0) {
      final kP = (widget.prices['kunjut_price'] as num?)
          ?.toInt() ?? 30000;
      extras.add({
        'name': '🌻 Кунжут',
        'count': _kunjutCount, 'unit': 'нон',
        'total': (2 / 1000 * kP * _kunjutCount).round(),
      });
    }
    if (_semechkaCount > 0) {
      final sP = (widget.prices['semechka_price'] as num?)
          ?.toInt() ?? 60000;
      extras.add({
        'name': '🌱 Семечка',
        'count': _semechkaCount, 'unit': 'нон',
        'total': (5 / 1000 * sP * _semechkaCount).round(),
      });
    }
    if (_oilCount > 0) {
      extras.add({
        'name': '🫙 Ўсимлик ёғи',
        'count': _oilCount, 'unit': 'нон',
        'total': _oilCost(),
      });
    }
    if (_sedanaCount > 0) {
      final dP = (widget.prices['sedana_price'] as num?)
          ?.toInt() ?? 50000;
      extras.add({
        'name': '🖤 Қора седана',
        'count': _sedanaCount, 'unit': 'нон',
        'total': (5 / 1000 * dP * _sedanaCount).round(),
      });
    }
    for (final p in _extraProductsList) {
      final id    = p['id'] as int;
      final count = _extraProductsCart[id] ?? 0;
      if (count > 0) {
        final discount = _extraDiscount(p, count);
        final fid = p['firestoreId'] as String?;
        extras.add({
          'name': p['name'],
          'count': count,
          'unit': p['unit'] == 'kg' ? 'kg' : 'дона',
          if (discount > 0) 'bonusDiscount': discount,
          if (discount > 0) 'bonusPercent': (p['bonusPercent'] as num?)?.toInt() ?? 0,
          if (fid != null && fid.isNotEmpty) 'firestoreId': fid,
          'total': _extraLineTotal(p, count),
        });
      }
    }

    return {
      'type':      'bread',
      'userName':  name,
      'userPhone': phone,
      'address':   addr,
      'phone':     phone,
      'items':     items,
      'extras':    extras,
      'total':     _grandTotal,
      'status':    'new',
      // ✅ 2-тузатиш: Timestamp.now() ишлатилди
      'createdAt': Timestamp.now(),
    };
  }

  Future<void> _sendOrder() async {
    final name  = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final addr  = _addrCtrl.text.trim();

    if (name.isEmpty) {
      _showError('Исмингизни киритинг'); return;
    }
    if (phone.isEmpty || phone.length < 9) {
      _showError('Телефон рақамини тўғри киритинг'); return;
    }
    if (addr.isEmpty) {
      _showError('Манзилни киритинг'); return;
    }

    setState(() => _isSending = true);

    try {
      final orderData = _buildOrderData(name, phone, addr);

      if (!widget.hasInternet) {
        final offlineData = Map<String, dynamic>.from(orderData);
        offlineData['createdAt'] = DateTime.now().toIso8601String();
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final existing = jsonDecode(
            prefs.getString('pending_orders') ?? '[]') as List;
        existing.add(offlineData);
        await prefs.setString('pending_orders', jsonEncode(existing));
        if (!mounted) return;
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '📵 Интернет йўқ. Буюртма сақланди — '
                  'интернет келганда автоматик юборилади.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
        widget.onOrderSent();
        return;
      }

      await _db.collection('orders').add(orderData);
      if (!mounted) return;
      setState(() => _isSending = false);
      widget.onOrderSent();

    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showError('Хатолик: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('🛒 Сават',
                style: TextStyle(fontSize: AppText.titleLarge, fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(onTap: widget.onClose,
                child: const Icon(Icons.close, color: Colors.grey)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('📦 Буюртма',
                  style: TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...widget.cart.entries.map((entry) {
                final p = widget.allProducts.firstWhere(
                        (p) => p['id'] == entry.key, orElse: () => {});
                if (p.isEmpty) return const SizedBox();
                final type = p['type'] as String;
                return _cartItem(p, entry.value, type == 'ёпиш' || type == 'той');
              }),

              if (_yopishTotalCount > 0) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Text('🌿 Қўшимча масаллиқлар',
                      style: TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _green, borderRadius: BorderRadius.circular(10)),
                    child: const Text('ИХТИЁРИЙ',
                        style: TextStyle(fontSize: AppText.labelTiny,
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 8),
                _extrasCountItem(emoji: '🌻', name: 'Кунжут дони', qty: '2г/нон',
                    count: _kunjutCount, max: _yopishTotalCount,
                    onChanged: (v) {
                      setState(() => _kunjutCount = v);
                      widget.onKunjutChanged(v);
                    }),
                const SizedBox(height: 6),
                _extrasCountItem(emoji: '🌱', name: 'Семечка дони', qty: '5г/нон',
                    count: _semechkaCount, max: _yopishTotalCount,
                    onChanged: (v) {
                      setState(() => _semechkaCount = v);
                      widget.onSemechkaChanged(v);
                    }),
                const SizedBox(height: 6),
                _extrasCountItem(emoji: '🫙', name: 'Ўсимлик ёғи', qty: 'ун/10кг=1л',
                    count: _oilCount, max: _yopishTotalCount,
                    onChanged: (v) {
                      setState(() => _oilCount = v);
                      widget.onOilChanged(v);
                    }),
                const SizedBox(height: 6),
                _extrasCountItem(emoji: '🖤', name: 'Қора седана', qty: '5г/нон',
                    count: _sedanaCount, max: _yopishTotalCount,
                    onChanged: (v) {
                      setState(() => _sedanaCount = v);
                      widget.onSedanaChanged(v);
                    }),
              ],

              if (_extraProductsList.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('🛒 Қўшимча маҳсулотлар',
                    style: TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final p in _extraProductsList) ...[
                  if ((p['bonusEnabled'] ?? false) == true &&
                      ((p['bonusThreshold'] as num?)?.toInt() ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '🎁 ${p['bonusThreshold']} дан бошлаб бонус: '
                        '${p['bonusQty'] ?? 0} тага ${p['bonusPercent'] ?? 0}% чегирма',
                        style: TextStyle(fontSize: AppText.labelTiny, color: Colors.orange.shade700),
                      ),
                    ),
                  _extrasCountItem(
                    emoji: '🛒',
                    name:  p['name'] ?? '',
                    qty:   '${p['qty']} ${p['unit'] == 'kg' ? 'кг' : 'дона'} — ${widget.fmtPrice((p['price'] as num?)?.toInt() ?? 0)} сўм',
                    count: _extraProductsCart[p['id'] as int] ?? 0,
                    max:   _extraProductMaxQty(p),
                    onChanged: (v) {
                      setState(() {
                        final id = p['id'] as int;
                        if (v <= 0) {
                          _extraProductsCart.remove(id);
                        } else {
                          _extraProductsCart[id] = v;
                        }
                      });
                      widget.onExtraCartChanged(p['id'] as int, v);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ],

              const SizedBox(height: 16),
              _buildPriceSummary(),
              const SizedBox(height: 16),

              const Text('👤 Маълумотлар',
                  style: TextStyle(fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _inputField(_nameCtrl,  '👤 Исм',    TextInputType.name),
              const SizedBox(height: 8),
              _inputField(_addrCtrl,  '📍 Манзил', TextInputType.streetAddress),
              const SizedBox(height: 8),
              _inputField(_phoneCtrl, '📞 Телефон', TextInputType.phone),
              const SizedBox(height: 20),

              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendOrder,
                  icon: _isSending
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                  label: Text(_isSending ? 'Юборилмоқда...' : 'ТАСДИҚЛАЙМАН',
                      style: const TextStyle(
                          fontSize: AppText.titleSmall, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text('Буюртма юборилгандан кейин тасдиқланса хабар берамиз',
                  style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey.shade400),
                  textAlign: TextAlign.center)),
            ],
          ),
        )),
      ]),
    );
  }

  Widget _cartItem(Map<String, dynamic> p, int count, bool needsFlourMilk) {
    final id     = p['id'] as int;
    final type   = p['type'] as String;
    final choice = _flourMilkChoice[id] ?? 'ours';
    final color  = type == 'ёпиш' ? _orange : _green;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(p['emoji'] ?? '🫓', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text(p['name'], style: const TextStyle(
              fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600))),
          Text('× $count', style: TextStyle(
              fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold, color: color)),
        ]),
        if (needsFlourMilk) ...[
          const SizedBox(height: 8),
          const Text('Ун ва сут:',
              style: TextStyle(fontSize: AppText.labelSmall, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _choiceBtn('🏠 Биздан', 'ours', choice == 'ours',
                    () => setState(() => _flourMilkChoice[id] = 'ours'))),
            const SizedBox(width: 8),
            Expanded(child: _choiceBtn('🧑 Сиздан', 'yours', choice == 'yours',
                    () => setState(() => _flourMilkChoice[id] = 'yours'))),
          ]),
          if (choice == 'ours') ...[
            const SizedBox(height: 4),
            _flourMilkInfo(p, count),
          ],
        ],
      ]),
    );
  }

  Widget _choiceBtn(String label, String val, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _green : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? _green : Colors.grey.shade300),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.bodySmall, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }

  Widget _flourMilkInfo(Map<String, dynamic> p, int count) {
    final flourG = (p['flour_g'] as num?)?.toInt() ?? 300;
    final milkMl = (p['milk_ml'] as num?)?.toInt()
        ?? ((p['milk_ratio'] as num?)?.toDouble() ?? 0.575 * flourG).round();
    final cost   = _flourMilkCost(p, count);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _green.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(child: Text(
          '🌾 Ун: ${flourG * count}г  🥛 Сут: ${milkMl * count}мл',
          style: const TextStyle(fontSize: AppText.labelSmall, color: Colors.grey),
        )),
        Text('+${widget.fmtPrice(cost)} сўм',
            style: const TextStyle(fontSize: AppText.labelSmall,
                fontWeight: FontWeight.bold, color: _green)),
      ]),
    );
  }

  Widget _extrasCountItem({
    required String emoji, required String name, required String qty,
    required int count, required int max, required ValueChanged<int> onChanged,
  }) {
    final selected = count > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF3E0) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? _green : Colors.grey.shade200,
            width: selected ? 1.5 : 1),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(
              fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
          Text(qty, style: TextStyle(
              fontSize: AppText.labelTiny, color: Colors.grey.shade500)),
        ])),
        Row(children: [
          GestureDetector(
            onTap: count > 0 ? () => onChanged(count - 1) : null,
            child: Container(width: 28, height: 28,
                decoration: BoxDecoration(
                    color: count > 0 ? _green.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: count > 0 ? _green.withOpacity(0.3) : Colors.grey.shade200)),
                child: Icon(Icons.remove, size: 14,
                    color: count > 0 ? _green : Colors.grey.shade400)),
          ),
          Container(width: 36, alignment: Alignment.center,
              child: Text(count == 0 ? '0' : '$count та',
                  style: TextStyle(fontSize: AppText.bodySmall, fontWeight: FontWeight.bold,
                      color: count > 0 ? _green : Colors.grey.shade400))),
          GestureDetector(
            onTap: count < max ? () => onChanged(count + 1) : null,
            child: Container(width: 28, height: 28,
                decoration: BoxDecoration(
                    color: count < max ? _green.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: count < max ? _green.withOpacity(0.3) : Colors.grey.shade200)),
                child: Icon(Icons.add, size: 14,
                    color: count < max ? _green : Colors.grey.shade400)),
          ),
        ]),
      ]),
    );
  }

  Widget _buildPriceSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.3)),
      ),
      child: Column(children: [
        ...widget.cart.entries.map((entry) {
          final p = widget.allProducts.firstWhere(
                  (p) => p['id'] == entry.key, orElse: () => {});
          if (p.isEmpty) return const SizedBox();
          return _summaryRow(
              '${p['emoji']} ${p['name']} × ${entry.value}',
              widget.fmtPrice(widget.productPrice(p) * entry.value));
        }),
        ...widget.cart.entries.map((entry) {
          final p = widget.allProducts.firstWhere(
                  (p) => p['id'] == entry.key, orElse: () => {});
          if (p.isEmpty) return const SizedBox();
          final type   = p['type'] as String;
          final choice = _flourMilkChoice[entry.key] ?? 'yours';
          if ((type == 'ёпиш' || type == 'той') && choice == 'ours') {
            return _summaryRow('  🌾 Ун+Сут (${p['name']})',
                widget.fmtPrice(_flourMilkCost(p, entry.value)), color: _green);
          }
          return const SizedBox();
        }),
        if (_kunjutCount > 0 && _yopishTotalCount > 0)
          _summaryRow('🌻 Кунжут', widget.fmtPrice(
              (2/1000*(widget.prices['kunjut_price'] as num? ?? 30000)*_kunjutCount).round()),
              color: _green),
        if (_semechkaCount > 0 && _yopishTotalCount > 0)
          _summaryRow('🌱 Семечка', widget.fmtPrice(
              (5/1000*(widget.prices['semechka_price'] as num? ?? 60000)*_semechkaCount).round()),
              color: _green),
        if (_oilCount > 0 && _yopishTotalCount > 0)
          _summaryRow('🫙 Ўсимлик ёғи', widget.fmtPrice(_oilCost()), color: _green),
        if (_sedanaCount > 0 && _yopishTotalCount > 0)
          _summaryRow('🖤 Қора седана', widget.fmtPrice(
              (5/1000*(widget.prices['sedana_price'] as num? ?? 50000)*_sedanaCount).round()),
              color: _green),
        for (final p in _extraProductsList) ...[
          if ((_extraProductsCart[p['id'] as int] ?? 0) > 0) ...[
            _summaryRow(
              '🛒 ${p['name']}',
              widget.fmtPrice(_extraLineTotal(
                  p, (_extraProductsCart[p['id'] as int] ?? 0))),
              color: _green,
            ),
            if (_extraDiscount(p, (_extraProductsCart[p['id'] as int] ?? 0)) > 0)
              _summaryRow(
                '  🎁 Бонус',
                '-${widget.fmtPrice(_extraDiscount(p, (_extraProductsCart[p['id'] as int] ?? 0)))} сўм',
                color: Colors.orange.shade700,
              ),
          ],
        ],
        const Divider(height: 12),
        _summaryRow('🧂 Туз + Хамиртуруш + Дрожа',
            widget.fmtPrice(_saltYeastCost), color: Colors.orange.shade700),
        const Divider(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('💰 Жами:', style: TextStyle(
              fontSize: AppText.titleSmall, fontWeight: FontWeight.bold)),
          Text('${widget.fmtPrice(_grandTotal)} сўм',
              style: const TextStyle(fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold, color: _green)),
        ]),
      ]),
    );
  }

  Widget _summaryRow(String label, String val, {Color? color}) =>
      Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(
                fontSize: AppText.bodySmall, color: color ?? Colors.grey.shade700))),
            Text('$val сўм', style: TextStyle(
                fontSize: AppText.bodySmall, fontWeight: FontWeight.w600,
                color: color ?? Colors.black87)),
          ]));

  Widget _inputField(TextEditingController ctrl, String hint, TextInputType type) {
    return TextField(
      controller: ctrl, keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _green, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true, fillColor: Colors.grey.shade50,
      ),
    );
  }
}