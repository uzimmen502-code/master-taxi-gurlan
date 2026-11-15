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

/// Бозор карточкаси расмининг ПАСТКИ ЧАП бурчагидаги НИСБИЙ жой («Гурлан» / «Ҳазорасп тумани» /
/// «Тошкент», `relativeLocationLabel`) — «Бозорлар» 7–8-босқич (эга, 2026-11-15). Бўш бўлса — чизилмайди.
/// Фақат туман/вилоят даражаси: аниқ манзил ҳеч қачон бу ерга тушмайди.
class MarketLocationPill extends StatelessWidget {
  const MarketLocationPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 6,
      bottom: 6,
      right: 40,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          key: const ValueKey('market_location_pill'),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0x8A000000),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.place_outlined, size: 10, color: Colors.white),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}