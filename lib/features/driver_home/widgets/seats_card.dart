import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';

/// Бўш ўрин миқдори картаси — +/- тугмалари билан.
class SeatsCard extends StatelessWidget {
  const SeatsCard({
    super.key,
    required this.seatsLeft,
    required this.totalSeats,
    required this.onAdd,
    required this.onRemove,
  });

  final int seatsLeft;
  final int totalSeats;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFB71C1C);
  static const _orange = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final isFull = seatsLeft == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isFull ? _red.withOpacity(0.4) : _green.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Row(children: [
        Text(isFull ? '🚫' : '💺', style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFull
                    ? 'БЎШ ЖОЙ ҚОЛМАДИ — ҲАРАКАТ БОШЛАНГ!'
                    : '$seatsLeft та жой бўш',
                style: TextStyle(
                  fontSize: AppText.bodyMedium,
                  fontWeight: FontWeight.bold,
                  color: isFull ? _red : _green,
                ),
              ),
              Text('Жами: $totalSeats та ўрин',
                  style: TextStyle(
                      fontSize: AppText.labelSmall,
                      color: Colors.grey.shade500)),
            ],
          ),
        ),
        if (seatsLeft < totalSeats)
          GestureDetector(
            onTap: onRemove,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Icon(Icons.remove, size: 18, color: Colors.grey),
            ),
          ),
        if (seatsLeft > 0)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: _green.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_add, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text('+1',
                    style: TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ]),
            ),
          ),
      ]),
    );
  }
}
