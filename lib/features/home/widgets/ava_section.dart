import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Бўлимнинг ҳолати.
enum AvaSectionStatus {
  /// Маълумот юкланмоқда.
  loading,

  /// Маълумот бор — [AvaSection.child] кўрсатилади.
  ready,

  /// Маълумот йўқ — бўлим ўз ўрнида қолади, битта ихчам қаторга айланади.
  empty,

  /// Юклашда хатолик — ихчам қатор + «Қайта уриниш».
  error,
}

/// Бош саҳифанинг бўлим каркаси: сарлавҳа + «Барчаси →» + 4 та ҳолат.
///
/// Тавсиф талаби: «Бўш бўлим ўз ўрнида қолади ва битта ихчам қаторга
/// айланади». Шунинг учун [AvaSectionStatus.empty] да ҳам сарлавҳа
/// кўринади — бўлим саҳифадан йўқолиб кетмайди ва рўйхат «сакрамайди».
class AvaSection extends StatelessWidget {
  const AvaSection({
    super.key,
    required this.title,
    required this.status,
    this.child,
    this.onSeeAll,
    this.onRetry,
    this.emptyLabel,
    this.skeletonRows = 3,
  });

  final String title;
  final AvaSectionStatus status;

  /// `status == ready` бўлганда кўрсатиладиган мазмун.
  final Widget? child;

  /// «Барчаси →» — бўлимнинг тўлиқ саҳифасини очади. `null` бўлса тугма йўқ.
  final VoidCallback? onSeeAll;

  /// Хатолик ҳолатида қайта уриниш.
  final VoidCallback? onRetry;

  /// Бўш ҳолат матни; берилмаса `home_section_empty`.
  final String? emptyLabel;

  /// Юкланиш ҳолатидаги «скелет» қаторлар сони.
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: title, onSeeAll: onSeeAll),
        const SizedBox(height: AvaSpace.gap),
        switch (status) {
          AvaSectionStatus.ready =>
            child ?? const SizedBox.shrink(),
          AvaSectionStatus.loading => _Skeleton(rows: skeletonRows),
          AvaSectionStatus.empty => AvaNoticeRow(
              text: emptyLabel ?? context.tr('home_section_empty'),
              icon: Icons.inbox_outlined,
              color: c.ink3,
            ),
          AvaSectionStatus.error => AvaNoticeRow(
              text: context.tr('home_section_error'),
              icon: Icons.cloud_off_rounded,
              color: c.warn,
              actionLabel:
                  onRetry == null ? null : context.tr('home_section_retry'),
              onAction: onRetry,
            ),
        },
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // `Row` flex бўлмаган болани аввал ЧЕКСИЗ кенгликда ўлчайди, шунинг
    // учун узун ёрлиқ («Барчаси» нинг бошқа тилдаги варианти ёки 130%
    // шрифт) тугмани бутун қаторни тошириб юборадиган даражада кенг
    // қилиши мумкин эди. Тугмага қатъий юқори чегара қўямиз — ундан
    // ошса ичидаги матн ellipsis'га тушади, сарлавҳа эса қолган жойни
    // олади.
    // Тизим шрифти катталашганда «Барчаси» ёрлиғи сарлавҳани сиқиб қўяди:
    // қурилмада 130% да «Яқинингиздаги эъ…» бўлиб қирқилган эди. Шундай
    // ҳолатда тугма фақат стрелкага айланади — босиш майдони ва
    // Semantics ёрлиғи ўша-ўша қолади.
    final compact = MediaQuery.textScalerOf(context).scale(12) > 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSeeAll = constraints.maxWidth.isFinite
            ? constraints.maxWidth * (compact ? 0.22 : 0.45)
            : double.infinity;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
            ),
            if (onSeeAll != null) ...[
              const SizedBox(width: AvaSpace.gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxSeeAll),
                child: _SeeAllButton(onTap: onSeeAll!, iconOnly: compact),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// «Барчаси →» — босиш майдони камида 44.
class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onTap, this.iconOnly = false});

  final VoidCallback onTap;

  /// Катта шрифтда — фақат стрелка (сарлавҳага жой қолсин).
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final label = context.tr('home_section_see_all');
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
        child: ConstrainedBox(
          // Матн 130% гача катталашса ҳам босиш майдони кичраймайди ва
          // ёрлиқ қирқилмайди — шунинг учун қатъий баландлик эмас, минимум.
          constraints: const BoxConstraints(minHeight: AvaTap.minSize),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!iconOnly) ...[
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AvaText.caption.copyWith(color: c.brand),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Бўш / хатолик ҳолатининг ихчам қатори.
class AvaNoticeRow extends StatelessWidget {
  const AvaNoticeRow({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      constraints: const BoxConstraints(minHeight: AvaTap.minSize),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AvaSpace.gap),
          Expanded(
            child: Text(
              text,
              style: AvaText.caption.copyWith(color: c.ink2),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AvaSpace.gap),
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AvaRadius.chip),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  actionLabel!,
                  style: AvaText.caption.copyWith(color: c.brand),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Юкланиш «скелети» — мазмун келгунча жой эгаллаб туради, шунда рўйхат
/// маълумот келганда сакрамайди.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 8),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(AvaRadius.card),
              ),
            ),
          ),
      ],
    );
  }
}
