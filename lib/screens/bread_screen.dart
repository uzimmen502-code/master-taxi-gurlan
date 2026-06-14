import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class BreadScreen extends StatefulWidget {
  const BreadScreen({super.key});

  @override
  State<BreadScreen> createState() => _BreadScreenState();
}

class _BreadScreenState extends State<BreadScreen> {
  final List<Map<String, dynamic>> _cart = [];

  final List<Map<String, dynamic>> _products = [
    {'id': 1, 'name': 'Юпқа нон', 'type': 'ёпиш', 'price': 1000, 'image': 'assets/bread_yupqa.png'},
    {'id': 2, 'name': 'Чўрак', 'type': 'ёпиш', 'price': 1000, 'image': 'assets/bread_churak.png'},
    {'id': 3, 'name': 'Зоғора нон', 'type': 'тайёр', 'price': 12000, 'image': 'assets/beard_zogora.png'},
    {'id': 4, 'name': 'Қора нон', 'type': 'тайёр', 'price': 13000, 'image': 'assets/beard_qora.png'},
    {'id': 5, 'name': 'Кунжутли нон', 'type': 'тайёр', 'price': 14000, 'image': 'assets/beard_kunjut.png'},
    {'id': 6, 'name': 'Гўштли нон', 'type': 'тайёр', 'price': 18000, 'image': 'assets/beard_gosht.png'},
    {'id': 7, 'name': 'Қовоқли нон', 'type': 'тайёр', 'price': 15000, 'image': 'assets/bread_qovoq.png'},
    {'id': 8, 'name': 'Ёнғоқли нон', 'type': 'тайёр', 'price': 16000, 'image': 'assets/bread_yongok.png'},
    {'id': 9, 'name': 'Той нон', 'type': 'тайёр', 'price': 20000, 'image': 'assets/beard_toy.png'},
    {'id': 10, 'name': 'Сомса', 'type': 'тайёр', 'price': 8000, 'image': 'assets/somsa.png'},
    {'id': 11, 'name': 'Пицца', 'type': 'тайёр', 'price': 35000, 'image': 'assets/pizza.png'},
    {'id': 12, 'name': 'Хачипури', 'type': 'тайёр', 'price': 25000, 'image': 'assets/xachipuri.png'},
  ];

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      _cart.add(product);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product['name']} саватга қўшилди'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations?.translate('bread') ?? 'Нон буюртма'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart),
                onPressed: _showCartDialog,
              ),
              if (_cart.isNotEmpty)
                Positioned(
                  right: 5,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('${_cart.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final product = _products[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.asset(
                      product['image'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.bakery_dining, size: 50, color: Colors.brown[300]),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                  child: Text(product['name'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: product['type'] == 'ёпиш' ? Colors.orange.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      product['type'] == 'ёпиш' ? 'Ёпиб бериш: ${product['price']} сўм' : 'Сотиш: ${product['price']} сўм',
                      style: TextStyle(fontSize: 11, color: product['type'] == 'ёпиш' ? Colors.orange.shade800 : Colors.green.shade800),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: ElevatedButton(
                    onPressed: () => _addToCart(product),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add, size: 18), SizedBox(width: 6), Text('Қўшиш')]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCartDialog() {
    int totalPrice = _cart.fold(0, (sum, item) => sum + (item['price'] as int));
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Сават'),
          content: _cart.isEmpty
              ? const SizedBox(height: 100, child: Center(child: Text('Сават бўш')))
              : SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return ListTile(
                        title: Text(item['name']),
                        subtitle: Text('${item['price']} сўм'),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () => setState(() => _cart.removeAt(index)),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Жами:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('$totalPrice сўм', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш')),
            if (_cart.isNotEmpty) ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Буюртма бериш')),
          ],
        );
      },
    );
  }
}