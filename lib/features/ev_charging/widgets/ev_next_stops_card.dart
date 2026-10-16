import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// «Кейинги тўхташлар: N та» — Google Maps'га ҳали юборилмаган тўхташлар
/// борлигини билдирувчи кичик чип (ҳар доим эришиш мумкин: босилса катта
/// карточка очилади). Бренд рангида (primaryText / onPrimary), матн
/// қирқилмайди — катта шрифтда (1.3) иккинчи қаторга ўтади.
class EvNextStopsChip extends StatelessWidget {
  const EvNextStopsChip({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        key: const ValueKey('ev_trip_next_chip'),
        color: Colors.white,
        elevation: 4,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.primaryDark, width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.ev_station_rounded,
                      size: 20, color: AppColors.primaryText),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      evNextStopsTitle(context, count),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Кейинги тўхташлар: N та».
String evNextStopsTitle(BuildContext context, int count) =>
    context.tr('ev_trip_next_stops').replaceAll('{n}', '$count');

/// Катта, аммо ихчам карточка: «Кейинги тўхташлар: N та» + катта «Давом
/// этиш» тугмаси. Машина юборилган охирги тўхташдан ўтгач ўзи чиқади ёки
/// ҳайдовчи чипни босса; ёпиш тугмаси уни яна чипга қайтаради.
class EvNextStopsCard extends StatelessWidget {
  const EvNextStopsCard({
    super.key,
    required this.count,
    required this.onContinue,
    required this.onClose,
    this.busy = false,
  });

  final int count;
  final VoidCallback onContinue;
  final VoidCallback onClose;

  /// Google Maps очилмоқда — тугма вақтинча ўчиқ (икки марта босилмасин).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('ev_trip_next_card'),
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.ev_station_rounded,
                    size: 22, color: AppColors.primaryText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    evNextStopsTitle(context, count),
                    key: const ValueKey('ev_trip_next_card_title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('ev_trip_next_close'),
                  tooltip: context.tr('close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.primaryText),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: ElevatedButton.icon(
                  key: const ValueKey('ev_trip_continue_button'),
                  onPressed: busy ? null : onContinue,
                  icon: const Icon(Icons.navigation_rounded, size: 24),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: const Color(0xFFBDBDBD),
                    disabledForegroundColor: const Color(0xFF616161),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  label: Text(
                    context.tr('ev_trip_continue'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
