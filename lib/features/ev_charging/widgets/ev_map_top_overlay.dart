import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Харита устидаги думалоқ «орқага» тугмаси (ярим шаффоф оқ). AppBar'нинг
/// оддий орқага стрелкаси билан бир хил белги ([BackButtonIcon]) ва бир хил
/// жой (чап юқори). EV харита ва сафар харитаси экранлари шуни ишлатади.
class EvMapBackButton extends StatelessWidget {
  const EvMapBackButton({super.key});

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.white.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: Tooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: const Center(
              child: IconTheme(
                data: IconThemeData(color: AppColors.onPrimary, size: 24),
                child: BackButtonIcon(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ⚡ Зарядлаш харитаси экранининг композицияси: харита БУТУН экранни
/// (статус бар ва пастки соҳа остигача) эгаллайди, устида сузиб юрувчи
/// «навигация» услубидаги тугмалар (эга қарори, 2026-10-16). AppBar ва
/// зарядлаш тури филтри чиплари йўқ.
///
/// Тоза композиция: харита ва ҳолат ташқаридан берилади, шунинг учун
/// `GoogleMap` платформа кўринишисиз тестланади.
class EvChargingMapLayout extends StatelessWidget {
  const EvChargingMapLayout({
    super.key,
    required this.loading,
    required this.map,
    required this.onAddStation,
    required this.onTripPlanner,
    this.errorText,
  });

  /// Юкланиш пайтида харита яширин, марказда спиннер.
  final bool loading;

  /// Тўлиқ экранли харита (юкланиб бўлгандан кейин кўрсатилади).
  final Widget map;

  final VoidCallback onAddStation;
  final VoidCallback onTripPlanner;

  /// GPS йўқлиги ҳақида огоҳлантириш (харитани тўсмайди).
  final String? errorText;

  /// Хаританинг ўз тугмалари (жойлашув тугмаси, логотип) устки панелнинг
  /// тагидан бошланиши учун: SafeArea юқори чегарасидан панель баландлиги.
  static double overlayHeight({required bool hasError}) =>
      EvMapTopOverlay.rowsHeight +
      (hasError ? EvMapTopOverlay.bannerHeight : 0);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        // Scaffold'да AppBar йўқ — body бутун экран (статус бар остида ҳам).
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (loading)
              const Center(child: CircularProgressIndicator())
            else
              map,
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: EvMapTopOverlay(
                  loading: loading,
                  errorText: errorText,
                  onAddStation: onAddStation,
                  onTripPlanner: onTripPlanner,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Устки сузиб юрувчи панель:
///   1-қатор: [орқага] + [«Станция қўшиш» — шаффоф панель];
///   2-қатор: «Қаерга борамиз?»;
///   3: (GPS йўқ бўлса) кичик огоҳлантириш қатори.
/// Юкланиш пайтида фақат орқага тугмаси кўринади.
class EvMapTopOverlay extends StatelessWidget {
  const EvMapTopOverlay({
    super.key,
    required this.loading,
    required this.onAddStation,
    required this.onTripPlanner,
    this.errorText,
  });

  final bool loading;
  final VoidCallback onAddStation;
  final VoidCallback onTripPlanner;
  final String? errorText;

  static const double _pad = 12;
  static const double _gap = 8;
  static const double barHeight = 48;

  /// Икки қатор (орқага/қўшиш + сафар) эгаллайдиган баландлик.
  static const double rowsHeight = _pad + barHeight + _gap + barHeight + _gap;

  /// Огоҳлантириш қатори баландлиги (оралиқ билан).
  static const double bannerHeight = 36 + _gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const ValueKey('ev_map_top_row'),
            children: [
              const EvMapBackButton(),
              if (!loading) ...[
                const SizedBox(width: _gap),
                Expanded(child: EvPaidAddStationBar(onTap: onAddStation)),
              ],
            ],
          ),
          if (!loading) ...[
            const SizedBox(height: _gap),
            // ⚡ «Қаерга борамиз?» — EV модули оддий станциялар харитаси
            // бўлиб қолмаслиги учун сафар ёрдамчиси.
            EvTripPlannerBar(onTap: onTripPlanner),
            if (errorText != null) ...[
              const SizedBox(height: _gap),
              EvMapGpsBanner(text: errorText!),
            ],
          ],
        ],
      ),
    );
  }
}

/// GPS йўқ — станциялар барибир кўринади, кичик сузиб юрувчи огоҳлантириш
/// (аввал `MaterialBanner` эди; харитани тўсмайди ва босилмайди).
class EvMapGpsBanner extends StatelessWidget {
  const EvMapGpsBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined,
                size: 18, color: AppColors.primaryText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ⚡ «Қаерга борамиз?» — сафар ёрдамчисига кириш. Кўриниши ва хулқи
/// ўзгаришсиз: оқ, [AppColors.primaryText] контур, йўл белгиси.
class EvTripPlannerBar extends StatelessWidget {
  const EvTripPlannerBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryText, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.route_rounded,
                  color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Text(
                context.tr('ev_trip_entry'),
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Станция қўшиш (пуллик)» — ТЎЛИҚ ШАФФОФ панель (эга қарори, 2026-10-16):
/// фон, соя, контур йўқ; босиш майдони ([InkWell]) бутун панель бўйлаб
/// сақланган. Харитада ўқилиши учун матн ва белги тўқ ([AppColors.onPrimary])
/// ва атрофида оқ «ҳошия» — ёруғ ҳам, қоронғи харита плиткасида ўқилади.
/// «Пуллик» сигнали йўқолмаслиги учун кичик олтин белги сақланган.
class EvPaidAddStationBar extends StatelessWidget {
  const EvPaidAddStationBar({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _badgeGold = Color(0xFFF9A825);

  /// Оқ ҳошия: 8 томонга блюрсиз силжитилган соя + юмшоқ блюр.
  static const List<Shadow> halo = [
    Shadow(color: Colors.white, offset: Offset(1.5, 0), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(-1.5, 0), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(0, 1.5), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(0, -1.5), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(1.1, 1.1), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(-1.1, 1.1), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(1.1, -1.1), blurRadius: 0),
    Shadow(color: Colors.white, offset: Offset(-1.1, -1.1), blurRadius: 0),
    Shadow(color: Colors.white, blurRadius: 4),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('ev_add_station_bar'),
      // Фон, соя ва контур йўқ — фақат босиш майдони.
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: AppColors.onPrimary,
                size: 22,
                shadows: halo,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Станция қўшиш',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    shadows: halo,
                  ),
                ),
              ),
              SizedBox(width: 8),
              _PaidBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaidBadge extends StatelessWidget {
  const _PaidBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: EvPaidAddStationBar._badgeGold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'пуллик',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
