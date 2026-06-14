import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/cart_item.dart';

class CartScreen extends StatefulWidget {
  final List<CartItem> cart;

  const CartScreen({super.key, required this.cart});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _useOwnIngredients = true;
  double _flourPrice = 8000;
  double _milkPrice = 5000;

  double get _totalPrice {
    double total = 0;
    for (var item in widget.cart) {
      total += item.totalPrice;
    }
    if (!_useOwnIngredients) {
      for (var item in widget.cart) {
        if (item.bread.isBakingService) {
          final ingredients = item.bread.getIngredients(item.quantity);
          total += (ingredients['flour']! * _flourPrice);
          total += (ingredients['milk']! * _milkPrice);
        }
      }
    }
    return total;
  }

  Map<String, double> get _totalIngredients {
    double flour = 0;
    double milk = 0;
    for (var item in widget.cart) {
      if (item.bread.isBakingService && _useOwnIngredients) {
        final ingredients = item.bread.getIngredients(item.quantity);
        flour += ingredients['flour']!;
        milk += ingredients['milk']!;
      }
    }
    return {'flour': flour, 'milk': milk};
  }

  Future<void> _placeOrder() async {
    final order = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'date': '${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
      'items': widget.cart.map((item) => {
        'name': item.bread.name,
        'quantity': item.quantity,
        'price': item.totalPrice,
        'useOwnIngredients': item.useOwnIngredients,
      }).toList(),
      'total': _totalPrice,
      'useOwnIngredients': _useOwnIngredients,
      'ingredients': _totalIngredients,
      'status': 'pending',
    };

    final prefs = await SharedPreferences.getInstance();
    final String? ordersJson = prefs.getString('bread_orders');
    List<dynamic> orders = [];
    if (ordersJson != null) {
      orders = jsonDecode(ordersJson);
    }
    orders.insert(0, order);
    await prefs.setString('bread_orders', jsonEncode(orders));

    widget.cart.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Буюртма қабул қилинди!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Нонвойхона сиз билан боғланади',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = _totalIngredients;
    final bool hasBakingService = widget.cart.any((item) => item.bread.isBakingService);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Саватча',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.cart.length,
              itemBuilder: (context, index) {
                final item = widget.cart[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: item.bread.isBakingService ? Colors.orange.shade50 : Colors.brown.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item.bread.isBakingService ? Icons.bakery_dining : Icons.dining,
                        color: item.bread.isBakingService ? Colors.orange : Colors.brown,
                      ),
                    ),
                    title: Text(item.bread.name),
                    subtitle: Text('${item.quantity} дона'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} сўм',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () {
                            setState(() {
                              widget.cart.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                if (hasBakingService) ...[
                  SwitchListTile(
                    title: const Text('Ўз масаллиғим билан'),
                    subtitle: const Text('Ун ва сут ўзимники'),
                    value: _useOwnIngredients,
                    onChanged: (value) {
                      setState(() {
                        _useOwnIngredients = value;
                      });
                    },
                  ),
                  if (_useOwnIngredients && (ingredients['flour']! > 0 || ingredients['milk']! > 0))
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (ingredients['flour']! > 0)
                            Text('🍚 Ун: ${ingredients['flour']!.toStringAsFixed(1)} кг'),
                          if (ingredients['milk']! > 0)
                            Text('🥛 Сут: ${ingredients['milk']!.toStringAsFixed(2)} л'),
                        ],
                      ),
                    ),
                  if (!_useOwnIngredients)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Масаллиқ нонвойхонадан олинади'),
                    ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Жами:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} сўм',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _placeOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'БУЮРТМА БЕРИШ',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}