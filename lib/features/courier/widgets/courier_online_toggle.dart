import 'package:flutter/material.dart';

/// Kuryer paneli AppBar tugmasi — online/offline holatini almashtiradi.
class CourierOnlineToggle extends StatelessWidget {
  const CourierOnlineToggle({
    super.key,
    required this.isOnline,
    required this.onToggle,
  });

  final bool isOnline;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOnline ? Colors.green.shade400 : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
            style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
