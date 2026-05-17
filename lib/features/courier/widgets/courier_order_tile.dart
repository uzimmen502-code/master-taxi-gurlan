import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/order_model.dart';

/// Kuryer marshrutidagi bitta buyurtma kartochkasi.
///
/// `isDone` — yetkazilgan (kulrang ko'rinish).
/// `isCurrent` — joriy buyurtma (yashil chegara + amal tugmalari).
class CourierOrderTile extends StatelessWidget {
  const CourierOrderTile({
    super.key,
    required this.order,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    required this.onDelivered,
  });

  final OrderModel order;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback onDelivered;

  static const Color _blue = Color(0xFF1565C0);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _orange = Color(0xFFE65100);

  Future<void> _call() async {
    if (order.userPhone.isEmpty) return;
    final url = Uri(scheme: 'tel', path: order.userPhone);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigate() async {
    if (!order.hasCoordinates) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${order.lat},${order.lng}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsPreview = order.items
        .take(2)
        .map((e) => '${e.name} ×${e.count}')
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDone ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? Colors.grey.shade200
              : isCurrent
                  ? _green
                  : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                    color: _green.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _indexBadge(),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          order.userName.isNotEmpty
                              ? order.userName
                              : order.userPhone,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDone
                                  ? Colors.grey.shade400
                                  : Colors.black87)),
                      Text(order.address,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
                if (isDone)
                  const Icon(Icons.check_circle, color: _green, size: 20)
                else if (isCurrent)
                  const Icon(Icons.navigation, color: _green, size: 20),
              ]),
              const SizedBox(height: 6),
              Text(
                itemsPreview,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (isCurrent)
                Row(children: [
                  _smallButton(
                      icon: Icons.call,
                      label: 'Қўнғироқ',
                      color: _blue,
                      onTap: _call),
                  const SizedBox(width: 6),
                  _smallButton(
                      icon: Icons.navigation,
                      label: 'Навигация',
                      color: _orange,
                      onTap: _navigate),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: onDelivered,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    child: const Text('ЕТКАЗИЛДИ ✅'),
                  ),
                ]),
            ]),
      ),
    );
  }

  Widget _indexBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isDone
            ? Colors.grey.shade300
            : isCurrent
                ? _green
                : Colors.orange.shade100,
        shape: BoxShape.circle,
      ),
      child: Center(
          child: Text('${index + 1}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDone
                      ? Colors.grey
                      : isCurrent
                          ? Colors.white
                          : _orange))),
    );
  }

  Widget _smallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
