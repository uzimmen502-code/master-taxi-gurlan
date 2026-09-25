import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';
import 'ava_card.dart';

/// Нарх — 14/800, бренд рангида.
///
/// Атайлаб `Expanded`/`ellipsis` ичига солинмаган: тавсиф талаби бўйича
/// шрифт 130% гача катталашганда нарх **қирқилмаслиги** керак, шунинг
/// учун у керакли жойни олади ва чапдаги устун торайтирилади.
class AvaPrice extends StatelessWidget {
  const AvaPrice({super.key, required this.text, this.note});

  final String text;

  /// Нарх остидаги изоҳ — масалан «ўрин», «кг».
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: AvaText.price.copyWith(color: c.brand)),
        if (note != null && note!.isNotEmpty)
          Text(note!, style: AvaText.caption.copyWith(color: c.ink3)),
      ],
    );
  }
}

/// 2–5-бўлимларнинг бир хил қатори: сарлавҳа + мета + нарх.
///
/// Мета сатри — матн ёки [AvaChip] лар аралашмаси; у `Wrap` ичида, шунинг
/// учун тор экранда ёки катта шрифтда кейинги қаторга тушади, тошиб
/// кетмайди.
class AvaListRow extends StatelessWidget {
  const AvaListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.meta = const [],
    this.price,
    this.priceNote,
    this.leading,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final List<Widget> meta;
  final String? price;
  final String? priceNote;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AvaCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AvaTap.minSize - 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AvaText.productName.copyWith(color: c.ink),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AvaText.caption.copyWith(color: c.ink2),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: meta),
                  ],
                ],
              ),
            ),
            if (price != null && price!.isNotEmpty) ...[
              const SizedBox(width: 10),
              AvaPrice(text: price!, note: priceNote),
            ],
          ],
        ),
      ),
    );
  }
}

/// Расмли ён томонга айланадиган карточка (6–8-бўлимлар: бозорлар).
class AvaTileCard extends StatelessWidget {
  const AvaTileCard({
    super.key,
    required this.title,
    this.image,
    this.price,
    this.priceNote,
    this.footnote,
    this.width = 148,
    this.onTap,
  });

  final String title;

  /// Расм виджети (масалан `CachedNetworkImage`); `null` бўлса ўрин эгаси.
  final Widget? image;
  final String? price;
  final String? priceNote;

  /// Пастки хира қатор — ҳудуд, етказиш муддати.
  final String? footnote;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AvaCard(
      onTap: onTap,
      width: width,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AvaRadius.card - 4),
            child: AspectRatio(
              aspectRatio: 1,
              child: image ??
                  ColoredBox(
                    color: c.surface2,
                    child: Icon(
                      Icons.image_outlined,
                      color: c.ink3,
                      size: 28,
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AvaText.productName.copyWith(color: c.ink),
          ),
          if (price != null && price!.isNotEmpty) ...[
            const SizedBox(height: 4),
            // Нарх ва изоҳ — ёнма-ён эмас, устма-уст: катта шрифтда
            // «дан» каби изоҳ нархни сиқиб қўймасин.
            Text(price!, style: AvaText.price.copyWith(color: c.brand)),
            if (priceNote != null && priceNote!.isNotEmpty)
              Text(
                priceNote!,
                style: AvaText.caption.copyWith(color: c.ink3),
              ),
          ],
          if (footnote != null && footnote!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.caption.copyWith(color: c.ink3),
            ),
          ],
        ],
      ),
    );
  }
}
