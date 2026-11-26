import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/ava_tokens.dart';
import 'home_dating_section.dart' show datingSectionVisibleFor;

/// Бош саҳифа «енгил дизайн» (эга 2026-11-20): катта горизонтал карточкалар.
///
/// Ҳар карточка: чапда бир хил 100×64 расм ўрни, сарлавҳа (16/600) + қисқа изоҳ
/// (14, `ink2`), ўнгда кулранг стрелка. Фон оқ, ингичка чегара, радиус 16.
/// Катта тизим шрифтида карточка баландлиги ўсади (матн кесилмайди), расм ўрни 100×64 қолади.
const double kHomeLiteImageWidth = 100;
const double kHomeLiteImageHeight = 64;

/// Расм ўрнида нима туради.
enum HomeLiteImageFit {
  /// Расм бутун ўринни қоплайди (бозор/баннер фотолари).
  cover,

  /// Кичик хизмат расми/иконкаси кулранг ўрин ўртасида.
  contain,
}

@immutable
class HomeLiteCardData {
  const HomeLiteCardData({
    required this.id,
    required this.title,
    required this.caption,
    required this.onTap,
    this.imagePath,
    this.icon,
    this.fit = HomeLiteImageFit.cover,
  });

  /// Калит учун: `home_lite_card_<id>`.
  final String id;
  final String title;
  final String caption;
  final VoidCallback onTap;

  /// Ассет йўли (`.svg` ҳам бўлади); `null` бўлса [icon].
  final String? imagePath;
  final IconData? icon;
  final HomeLiteImageFit fit;
}

/// Бўлим: сарлавҳа (18/600) + карточкалар (оралиқ 10). Карточка бўлмаса — ҳеч нарса.
class HomeLiteSection extends StatelessWidget {
  const HomeLiteSection({
    super.key,
    required this.title,
    required this.cards,
  });

  final String title;
  final List<HomeLiteCardData> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(top: AvaSpace.homeSection),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              key: const ValueKey('home_lite_section_title'),
              style: AvaText.homeSectionTitle.copyWith(color: c.ink),
            ),
          ),
          const SizedBox(height: AvaSpace.cardGap),
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AvaSpace.cardGap),
            HomeLiteCard(data: cards[i]),
          ],
        ],
      ),
    );
  }
}

class HomeLiteCard extends StatelessWidget {
  const HomeLiteCard({super.key, required this.data});

  final HomeLiteCardData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      key: ValueKey('home_lite_card_${data.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kHomeLiteImageHeight),
          // Расм ўрни эни доим 100; баландлиги — карточка баландлиги (камида 64): 2 қаторли
          // изоҳ ёки катта шрифтда ҳам расм четгача тўлади (оқ бўшлиқ қолмайди).
          child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: ValueKey('home_lite_image_${data.id}'),
                width: kHomeLiteImageWidth,
                // Ички баландлик 64 деб ҳисобланади (расм ўлчами карточкани чўзмасин);
                // жойлашувда Row (stretch) уни карточка баландлигига тортади.
                height: kHomeLiteImageHeight,
                child: _CardImage(data: data),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        key: ValueKey('home_lite_title_${data.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AvaText.homeCardTitle.copyWith(color: c.ink),
                      ),
                      if (data.caption.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.caption,
                          key: ValueKey('home_lite_caption_${data.id}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AvaText.homeCardCaption.copyWith(color: c.ink2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Center(child: Icon(Icons.chevron_right_rounded, size: 24, color: c.ink3)),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.data});

  final HomeLiteCardData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final path = data.imagePath;
    final placeholder = ColoredBox(
      color: c.surface2,
      child: Center(child: Icon(data.icon ?? Icons.image_outlined, size: 30, color: c.ink2)),
    );
    if (path == null) return placeholder;
    final contain = data.fit == HomeLiteImageFit.contain;
    final Widget img = path.toLowerCase().endsWith('.svg')
        ? SvgPicture.asset(path, fit: contain ? BoxFit.contain : BoxFit.cover)
        : Image.asset(
            path,
            fit: contain ? BoxFit.contain : BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (_, __, ___) => placeholder,
          );
    if (!contain) return img;
    return ColoredBox(
      color: c.surface2,
      child: Padding(padding: const EdgeInsets.all(10), child: img),
    );
  }
}

// ─── Карточка тартиби ва дарвозалари (ягона манба; тестланади) ─────────────

/// Пул ўтказмалари картаси очадиган модуллар — тартиб билан.
const kHomePayModuleIds = <String>['pay_payme', 'pay_click', 'pay_paynet'];

/// Кўринадиган тўлов модуллари; бўш бўлса «Пул ўтказмалари» картаси йўқ.
List<String> visiblePayModules(bool Function(String moduleId) isVisible) => [
      for (final id in kHomePayModuleIds)
        if (isVisible(id)) id,
    ];

/// «Эълон ва хизматлар» бўлими карточкалари (эга 2026-11-20), шу ТАРТИБДА:
/// Танишув (`dating` + ёш 18..45) · Янги эълонлар (`jobs`) · Почта жўнатиш (`logistics`) ·
/// Пул ўтказмалари (камида битта `pay_*`) · Кафе-ресторанлар (ўз дарвозаси, [restaurantsAllowed]).
///
/// Эга 2026-11-26: «Байрам саватчаси» (`holiday`, [holidayVisible] — `holidayCardVisible`) бўлим БОШИДА (жозибали,
/// юқорига яқин); «Яқинларингиз туғилган кунини қўшинг» (`relatives_bday`, [relativesPromptVisible] —
/// `relativesPromptVisible`: ≥ 3 туғилган кун бўлса яширин) ундан кейин.
List<String> homeAdsServicesCardIds({
  required bool Function(String moduleId) isVisible,
  required String viewerBirthDate,
  required bool restaurantsAllowed,
  bool holidayVisible = false,
  bool relativesPromptVisible = false,
}) =>
    [
      if (holidayVisible) 'holiday',
      if (holidayVisible && relativesPromptVisible) 'relatives_bday',
      if (isVisible('dating') && datingSectionVisibleFor(viewerBirthDate)) 'dating',
      if (isVisible('jobs')) 'ads',
      if (isVisible('logistics')) 'logistics',
      if (visiblePayModules(isVisible).isNotEmpty) 'pay',
      if (restaurantsAllowed) 'restaurants',
    ];

/// «Транспорт ва логистика» бўлими (эга 2026-11-20), шу тартибда. Халқаро такси/юк — кейинга қолдирилган.
const kHomeTransportModuleIds = <String>['intercity', 'local_taxi', 'marshrut', 'yuk_local'];

List<String> homeTransportCardIds(bool Function(String moduleId) isVisible) => [
      for (final id in kHomeTransportModuleIds)
        if (isVisible(id)) id,
    ];
