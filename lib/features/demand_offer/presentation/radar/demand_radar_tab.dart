// «ХАБАРЛАР» → «ТАЛАБ» ТАБИ (РАДАР).
//
// Эга қарори: радар янги пастки таб эмас, «Хабарлар» ичидаги ички таб
// (2026-10-03: пастки навигацияга янги таб қўшилмайди; 2026-10-20: «Хабарлар»
// ичида).
//
// Бу таб ЖАРАЁНни бошқармайди — фақат қисқа хулоса кўрсатади ва тўлиқ
// «Талаб ва таклифлар» экранига олиб боради. Сабаби: бошқарув (таклифларни
// солиштириш, қабул қилиш, бекор қилиш) ўша экранда, нусхаси иккинчи жойда
// бўлмасин. Хабар — ўқиб ўтиладиган нарса, талаб эса бошқариладиган жараён.
//
// Сонларни ота-ҳаб (`NewsHubScreen`) беради, таб ўзи Firestore'га уланмайди:
// (1) тестланади, (2) оқим бошланғич қийматни такрорламайди — таб кеч қурилса
// сон йўқолиб қолмасин, (3) ҳаб белгиси билан БИР хил манбадан.

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';

/// Саноқ матни: 99 гача — сон, ундан кўп — `99+`; манфий — `0`.
String radarCountText(int n) {
  if (n <= 0) return '0';
  return n > 99 ? '99+' : '$n';
}

class DemandRadarTab extends StatelessWidget {
  const DemandRadarTab({
    super.key,
    required this.userId,
    required this.activeDemands,
    required this.newMatches,
    required this.onOpen,
  });

  /// Канон телефон ID. Бўш/қисқа — фойдаланувчи кирмаган.
  final String userId;

  /// Менинг фаол сўровларим сони (харидор томони).
  final int activeDemands;

  /// Менга келган ЯНГИ сўровлар сони (таклифчи томони).
  final int newMatches;

  /// «Талаб ва таклифлар» тўлиқ экранини очиш.
  final VoidCallback onOpen;

  bool get _signedIn => userId.length >= 9;

  @override
  Widget build(BuildContext context) {
    if (!_signedIn) {
      return _EmptyHint(text: context.tr('radar_empty'));
    }
    final nothing = activeDemands <= 0 && newMatches <= 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (newMatches > 0)
          _CountCard(
            icon: Icons.notifications_active_rounded,
            label: context.tr('radar_new_incoming'),
            count: newMatches,
            highlight: true,
          ),
        if (activeDemands > 0)
          _CountCard(
            icon: Icons.assignment_rounded,
            label: context.tr('radar_my_active'),
            count: activeDemands,
          ),
        if (nothing) _EmptyHint(text: context.tr('radar_empty')),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onOpen,
          style: FilledButton.styleFrom(
            backgroundColor: context.ava.brand,
            foregroundColor: context.ava.brandInk,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            context.tr('radar_open'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.icon,
    required this.label,
    required this.count,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? c.brandSoft : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? c.brand : c.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: highlight ? c.brand : c.ink2),
          const SizedBox(width: 12),
          // Узун (рус) матн қирқилмасин, сон эса доим кўринсин.
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            radarCountText(count),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: highlight ? c.brand : c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.ava.ink2),
        ),
      ),
    );
  }
}
