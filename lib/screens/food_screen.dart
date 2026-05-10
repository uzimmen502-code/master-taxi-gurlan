import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  // ===== МАҲСУЛОТЛАР =====
  final List<Map<String, dynamic>> _products = [
    {
      'id': 1,
      'name': 'Ош',
      'emoji': '🍚',
      'price': 45000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Асосий',
      'desc': 'Тозалиги ва мазаси билан',
    },
    {
      'id': 2,
      'name': 'Товуқ табака',
      'emoji': '🍗',
      'price': 60000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Товуқ',
      'desc': 'Тандирда босиб пишган',
    },
    {
      'id': 3,
      'name': 'Товуқ қовурдоқ',
      'emoji': '🍳',
      'price': 55000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Товуқ',
      'desc': 'Зираворлар билан қовурилган',
    },
    {
      'id': 4,
      'name': 'Чўғда пишган товуқ',
      'emoji': '🔥',
      'price': 65000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Товуқ',
      'desc': 'Кўмир устида',
    },
    {
      'id': 5,
      'name': 'Сарёғда қовурилган товуқ',
      'emoji': '🧈',
      'price': 70000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Товуқ',
      'desc': 'Асл сарёғда',
    },
    {
      'id': 6,
      'name': 'Қовурилган балиқ',
      'emoji': '🐟',
      'price': 80000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Балиқ',
      'desc': 'Тоза балиқ, зираворлар билан',
    },
    {
      'id': 7,
      'name': 'Кўмирда пишган балиқ',
      'emoji': '🐠',
      'price': 90000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Балиқ',
      'desc': 'Кўмир ўтида',
    },
    {
      'id': 8,
      'name': 'Иликли шўрва',
      'emoji': '🍲',
      'price': 25000,
      'unit': 'литр',
      'minQty': 1.0,
      'step': 0.5,
      'category': 'Шўрва',
      'desc': 'Иссиқ, тўйимли',
    },
    {
      'id': 9,
      'name': 'Мастава',
      'emoji': '🥘',
      'price': 22000,
      'unit': 'литр',
      'minQty': 1.0,
      'step': 0.5,
      'category': 'Шўрва',
      'desc': 'Гуруч билан шўрва',
    },
    {
      'id': 10,
      'name': 'Димлама',
      'emoji': '🫕',
      'price': 50000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Асосий',
      'desc': 'Сабзавотлар билан дамланган гўшт',
    },
    {
      'id': 11,
      'name': 'Қовурдоқ',
      'emoji': '🥩',
      'price': 75000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Асосий',
      'desc': 'Думба ёғида қовурилган',
    },
    {
      'id': 12,
      'name': 'Шашлик',
      'emoji': '🍢',
      'price': 85000,
      'unit': 'кг',
      'minQty': 0.5,
      'step': 0.5,
      'category': 'Асосий',
      'desc': 'Кўмирда пишган',
    },
  ];

  // ===== КАТЕГОРИЯЛАР =====
  final List<String> _categories = [
    'Барчаси', 'Асосий', 'Товуқ', 'Балиқ', 'Шўрва'
  ];
  String _selectedCategory = 'Барчаси';

  // ===== САВАТ: { productId: qty } =====
  final Map<int, double> _cart = {};

  List<Map<String, dynamic>> get _filteredProducts {
    if (_selectedCategory == 'Барчаси') return _products;
    return _products.where((p) => p['category'] == _selectedCategory).toList();
  }

  int get _cartItemCount => _cart.length;

  int get _cartTotal {
    int total = 0;
    for (var entry in _cart.entries) {
      final product = _products.firstWhere((p) => p['id'] == entry.key);
      total += ((product['price'] as int) * entry.value).round();
    }
    return total;
  }

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      final id = product['id'] as int;
      final min = product['minQty'] as double;
      _cart[id] = (_cart[id] ?? 0) + min;
    });
  }

  void _increaseQty(int productId) {
    final product = _products.firstWhere((p) => p['id'] == productId);
    setState(() {
      _cart[productId] = (_cart[productId] ?? 0) + (product['step'] as double);
    });
  }

  void _decreaseQty(int productId) {
    final product = _products.firstWhere((p) => p['id'] == productId);
    final step = product['step'] as double;
    final min = product['minQty'] as double;
    setState(() {
      final current = _cart[productId] ?? 0;
      if (current <= min) {
        _cart.remove(productId);
      } else {
        _cart[productId] = current - step;
      }
    });
  }

  String _formatQty(double qty, String unit) {
    if (qty == qty.roundToDouble()) {
      return '${qty.toInt()} $unit';
    }
    return '$qty $unit';
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(' ');
      result.write(s[i]);
    }
    return result.toString();
  }

  // ===== САВАТ ДИАЛОГ =====
  void _showCart() {
    final loc = AppLocalizations.of(context)!;
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.translate('cart_empty')), duration: const Duration(seconds: 1)),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CartSheet(
        cart: _cart,
        products: _products,
        cartTotal: _cartTotal,
        formatQty: _formatQty,
        formatPrice: _formatPrice,
        onIncrease: (id) { _increaseQty(id); Navigator.pop(context); _showCart(); },
        onDecrease: (id) { _decreaseQty(id); if (_cart.isEmpty) { Navigator.pop(context); } else { Navigator.pop(context); _showCart(); } },
        onOrder: () { Navigator.pop(context); _showOrderForm(); },
      ),
    );
  }

  void _showOrderForm() {
    final loc = AppLocalizations.of(context)!;
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 16),
                Text('📋 ${loc.translate("order")}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: '📍 ${loc.translate("delivery_address")}',
                    hintText: loc.translate('delivery_address_hint'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '📞 ${loc.translate("phone_number")}',
                    hintText: loc.translate('enter_phone'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.phone, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('💰 ${loc.translate("total")}:', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${_formatPrice(_cartTotal)} ${loc.translate("sum")}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                  ]),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final address = addressCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      if (address.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(loc.translate('enter_address'))));
                        return;
                      }
                      if (phone.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(loc.translate('phone_number'))));
                        return;
                      }
                      Navigator.pop(context);
                      _confirmOrder(address, phone);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(loc.translate('confirm'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== БУЮРТМА ТАСДИҚЛАНДИ =====
  Future<void> _confirmOrder(String address, String phone) async {
    // Firebase га сақлаш
    try {
      final prefs     = await SharedPreferences.getInstance();
      final userName  = prefs.getString('user_name')  ?? '';
      final userPhone = prefs.getString('user_phone') ?? '';

      final items = _cart.entries.map((e) {
        final p    = _products.firstWhere((p) => p['id'] == e.key);
        final qty  = e.value;
        final unit = p['unit'] as String;
        return {
          'name':  p['name'],
          'emoji': p['emoji'],
          'price': p['price'],
          'qty':   qty,
          'unit':  unit,
          'total': ((p['price'] as int) * qty).round(),
        };
      }).toList();

      await FirebaseFirestore.instance.collection('orders').add({
        'type':      'food',
        'userName':  userName,
        'userPhone': userPhone,
        'address':   address,
        'phone':     phone,
        'items':     items,
        'total':     _cartTotal,
        'status':    'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (!mounted) return;

    // Буюртма матнини тайёрлаш
    final buffer = StringBuffer();
    for (var entry in _cart.entries) {
      final product = _products.firstWhere((p) => p['id'] == entry.key);
      final qty   = entry.value;
      final unit  = product['unit'] as String;
      final price = ((product['price'] as int) * qty).round();
      buffer.writeln('${product['emoji']} ${product['name']}: ${_formatQty(qty, unit)} = ${_formatPrice(price)} сўм');
    }

    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 28),
          const SizedBox(width: 8),
          Text(loc.translate('order_confirmed')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc.translate('will_contact_soon'),
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
            child: Text(buffer.toString(),
                style: const TextStyle(fontSize: 12)),
          ),
          const Divider(height: 16),
          Text('📍 $address', style: const TextStyle(fontSize: 12)),
          Text('📞 $phone',   style: const TextStyle(fontSize: 12)),
          Text('💰 ${_formatPrice(_cartTotal)} ${loc.translate("sum")}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
        ]),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final url = Uri.parse('tel:$phone');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            icon: const Icon(Icons.phone, size: 18),
            label: Text(loc.translate('call')),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _cart.clear());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(loc.translate('ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    // Категориялар локализация
    final localizedCategories = {
      'Барчаси': loc.translate('all_categories'),
      'Асосий':  loc.translate('main_dishes'),
      'Товуқ':   loc.translate('chicken'),
      'Балиқ':   loc.translate('fish'),
      'Шўрва':   loc.translate('soups'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('food_order')),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ===== КАТЕГОРИЯЛАР =====
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        localizedCategories[cat] ?? cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ===== МАҲСУЛОТЛАР РЎЙХАТИ =====
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                final id = product['id'] as int;
                final inCart = _cart.containsKey(id);
                final qty = _cart[id] ?? 0.0;
                final unit = product['unit'] as String;
                final price = product['price'] as int;
                final localizedUnit = unit == 'кг' ? loc.translate('kg') : loc.translate('litre');

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(product['emoji'], style: const TextStyle(fontSize: 32)),
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product['name'],
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text(product['desc'],
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              const SizedBox(height: 6),
                              Text(
                                '${_formatPrice(price)} ${loc.translate("sum")} / $localizedUnit',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        inCart
                            ? Container(
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green[300]!),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              onPressed: () => _decreaseQty(id),
                              icon: const Icon(Icons.remove, size: 18, color: Colors.green),
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            Text(_formatQty(qty, unit),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            IconButton(
                              onPressed: () => _increaseQty(id),
                              icon: const Icon(Icons.add, size: 18, color: Colors.green),
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ]),
                        )
                            : ElevatedButton(
                          onPressed: () => _addToCart(product),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            minimumSize: Size.zero,
                          ),
                          child: Text(loc.translate('add'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: _cartItemCount > 0
          ? FloatingActionButton.extended(
        onPressed: _showCart,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.shopping_basket),
            Positioned(
              top: -6, right: -6,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text('$_cartItemCount',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
        label: Text(
          '${_formatPrice(_cartTotal)} ${loc.translate("sum")}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ===== САВАТ BOTTOM SHEET =====
class _CartSheet extends StatelessWidget {
  final Map<int, double> cart;
  final List<Map<String, dynamic>> products;
  final int cartTotal;
  final String Function(double, String) formatQty;
  final String Function(int) formatPrice;
  final void Function(int) onIncrease;
  final void Function(int) onDecrease;
  final VoidCallback onOrder;

  const _CartSheet({
    required this.cart,
    required this.products,
    required this.cartTotal,
    required this.formatQty,
    required this.formatPrice,
    required this.onIncrease,
    required this.onDecrease,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final cartItems = cart.entries.map((e) {
      return products.firstWhere((p) => p['id'] == e.key);
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.shopping_basket, color: Colors.green),
            const SizedBox(width: 8),
            Text(loc.translate('cart'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${cart.length}', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ]),
          const SizedBox(height: 12),
          const Divider(),

          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final product = cartItems[index];
                final id = product['id'] as int;
                final qty = cart[id]!;
                final unit = product['unit'] as String;
                final itemTotal = ((product['price'] as int) * qty).round();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(product['emoji'], style: const TextStyle(fontSize: 24))),
                  ),
                  title: Text(product['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('${formatPrice(itemTotal)} ${loc.translate("sum")}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      onPressed: () => onDecrease(id),
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                    Text(formatQty(qty, unit),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => onIncrease(id),
                      icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    ),
                  ]),
                );
              },
            ),
          ),

          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${loc.translate("total")}:', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('${formatPrice(cartTotal)} ${loc.translate("sum")}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green)),
          ]),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: onOrder,
              icon: const Icon(Icons.delivery_dining),
              label: Text(loc.translate('place_order'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}