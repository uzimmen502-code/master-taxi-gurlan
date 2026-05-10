import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../l10n/app_localizations.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _localTaxiOrders = [];
  List<dynamic> _intercityOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final prefs = await SharedPreferences.getInstance();

    // ТЕСТ МАЪЛУМОТЛАРИ - МАҲАЛЛИЙ ТАКСИ
    if (prefs.getString('local_taxi_orders') == null) {
      final testLocalOrders = [
        {
          'id': '1',
          'from_address': 'Чилонзор, 19-квартал',
          'to_address': 'Юнусобод, 12-квартал',
          'price': 12500.0,
          'date': '22.04.2026',
          'driver_name': 'Сардор',
          'status': 'completed',
        },
        {
          'id': '2',
          'from_address': 'Миробод, А.Темур кўчаси',
          'to_address': 'Аэропорт',
          'price': 35000.0,
          'date': '21.04.2026',
          'driver_name': 'Баҳодир',
          'status': 'completed',
        },
        {
          'id': '3',
          'from_address': 'Чилонзор, 20-квартал',
          'to_address': 'Марказий вокзал',
          'price': 18000.0,
          'date': '20.04.2026',
          'driver_name': 'Акмал',
          'status': 'cancelled',
        },
      ];
      await prefs.setString('local_taxi_orders', jsonEncode(testLocalOrders));
    }

    // ТЕСТ МАЪЛУМОТЛАРИ - ШАҲАРЛАРАРО ТАКСИ
    if (prefs.getString('intercity_orders') == null) {
      final testIntercityOrders = [
        {
          'id': '1',
          'from_address': 'Гурлан • Хоразм',
          'to_address': 'Тошкент ш. • Чилонзор',
          'price': 150000.0,
          'date': '22.04.2026',
          'driver_name': 'Жамшид',
          'status': 'completed',
        },
        {
          'id': '2',
          'from_address': 'Урганч • Хоразм',
          'to_address': 'Тошкент ш. • Сергели',
          'price': 180000.0,
          'date': '18.04.2026',
          'driver_name': 'Шавкат',
          'status': 'completed',
        },
      ];
      await prefs.setString('intercity_orders', jsonEncode(testIntercityOrders));
    }

    // Маълумотларни юклаш
    final String? localOrdersJson = prefs.getString('local_taxi_orders');
    if (localOrdersJson != null) {
      setState(() {
        _localTaxiOrders = jsonDecode(localOrdersJson);
      });
    }

    final String? intercityOrdersJson = prefs.getString('intercity_orders');
    if (intercityOrdersJson != null) {
      setState(() {
        _intercityOrders = jsonDecode(intercityOrdersJson);
      });
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          loc.translate('order_history'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          tabs: [
            Tab(text: loc.translate('local_taxi_orders')),
            Tab(text: loc.translate('intercity_taxi_orders')),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(_localTaxiOrders, 'local'),
          _buildOrdersList(_intercityOrders, 'intercity'),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<dynamic> orders, String type) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Ҳозирча буюртмалар мавжуд эмас',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderCard(order, type);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, String type) {
    final String status = order['status'] ?? 'completed';
    final String fromAddress = order['from_address'] ?? 'Номаълум';
    final String toAddress = order['to_address'] ?? 'Номаълум';
    final double price = order['price'] ?? 0.0;
    final String date = order['date'] ?? '';
    final String driverName = order['driver_name'] ?? 'Номаълум';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusText = 'Якунланган';
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusText = 'Бекор қилинган';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Жараёнда';
        statusIcon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ҳолат ва сана
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  ),
                ),
                Text(
                  date,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Манзиллар
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 30,
                      color: Colors.grey.shade300,
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red, width: 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fromAddress,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        toAddress,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Ҳайдовчи ва нарх
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      driverName,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                Text(
                  '${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} сўм',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}