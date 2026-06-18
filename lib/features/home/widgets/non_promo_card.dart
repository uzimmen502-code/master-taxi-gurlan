import 'package:flutter/material.dart';

/// Non buyurtma promo banner.
class NonPromoCard extends StatelessWidget {
  const NonPromoCard({super.key, this.onTap});

  final VoidCallback? onTap;

  static const _green = Color(0xFF36A63A);
  static const _gold = Color(0xFFF5C518);
  static const _badgeText = Color(0xFF1A5E1C);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Non buyurtma qiling',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Yangi non — 500 so'm, eshigingizga",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Buyurtma →',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _badgeText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
