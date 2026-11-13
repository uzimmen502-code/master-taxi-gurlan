import 'package:flutter/material.dart';

/// Аралаш бозор карточкасининг ТЕПА ЎНГ бурчагидаги бозор белгиси (эга,
/// 2026-11-13): «Улгуржи» / «Хитой» — маҳсулот қайси бозорга тегишли.
/// Тепа чапдаги «AVA» / «Дўкон» белгиси билан устма-уст тушмайди.
class MarketCornerBadge extends StatelessWidget {
  const MarketCornerBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        key: const ValueKey('market_corner_badge'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xCC1F2937),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
