import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/geo/geo_names.dart';
import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/services/tv_clip_link.dart';
import '../controllers/jobs_controller.dart';
import '../jobs_colors.dart';
import 'complaint_sheet.dart';
import 'edit_ad_sheet.dart';

/// Эълонлар (mini-OLX) рўйхатидаги бир карта.
///
/// Аудит (2026-10-18): эга учун иккита бир хил "Таҳрирлаш" (қалам + тугма)
/// бор эди — қалам олиб ташланди; карточканинг матни босилса тўлиқ очилади
/// (тафсилот саҳифаси йўқ); "Қўнғироқ" яроқсиз телефонда жимгина қайтмайди;
/// манзил ўрнига фақат ҳудуд (туман) кўрсатилади — уй манзили эмас.
class AdCard extends StatefulWidget {
  const AdCard({
    super.key,
    required this.ad,
    this.highlighted = false,
    this.linkedClip,
  });

  final JobAd ad;

  /// Эълон эгаси қўшган видео (бор бўлса «▶» тугмаси чиқади). Эгалик
  /// текшируви чақирувчида ([JobsScreen]).
  final TvClip? linkedClip;

  /// Бош саҳифадаги қатордан айнан шу эълонга келинган — кўз дарҳол
  /// топиши учун контури қалин ва ранги ажралиб туради.
  final bool highlighted;

  /// Матн узун бўлса "Тўлиқ кўриш" ҳаволаси чиқади (тахминий чегара).
  @visibleForTesting
  static bool isLong(JobAd ad) {
    final headline = ad.title.trim().isNotEmpty ? ad.title : ad.text;
    final subline = ad.title.trim().isEmpty ? '' : ad.text;
    return headline.length > 70 || subline.length > 120;
  }

  @override
  State<AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<AdCard> {
  bool _expanded = false;

  JobAd get ad => widget.ad;

  Color get _kindColor => JobsColors.accentFor(ad.kind);

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void note(String text) => messenger.showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: _kindColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
    if (ad.authorPhone.isEmpty || phoneDigits(ad.authorPhone).length < 9) {
      note(context.tr('ad_details_phone_invalid'));
      return;
    }
    final failed = context.tr('ad_details_call_failed');
    try {
      final ok = await launchUrl(
        Uri.parse('tel:${phoneForCall(ad.authorPhone)}'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) note('$failed: ${ad.authorPhone}');
    } catch (_) {
      if (!context.mounted) return;
      note('$failed: ${ad.authorPhone}');
    }
  }

  Future<void> _report(BuildContext context) async {
    final c = context.read<JobsController>();
    if (c.isOwner(ad)) return;
    final reason = await showComplaintSheet(context);
    if (reason == null || reason.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await c.submitComplaint(adId: ad.id, reason: reason);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(result.success
          ? context.tr('ad_report_sent')
          : context.trMsg(result.error ?? 'jobs_err_generic')),
      backgroundColor:
          result.success ? JobsColors.bar : JobsColors.urgent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _edit(BuildContext context) {
    final c = context.read<JobsController>();
    showEditAdSheet(context: context, ad: ad, controller: c);
  }

  String get _body => ad.text;

  String get _headline {
    if (ad.title.trim().isNotEmpty) return ad.title;
    return _body;
  }

  String get _subline {
    if (ad.title.trim().isEmpty) return '';
    return _body;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    final mine = c.isOwner(ad);
    final canEdit = mine || c.isAdmin;
    final color = _kindColor;
    final highlighted = widget.highlighted;
    final linkedClip = widget.linkedClip;
    final long = AdCard.isLong(ad);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JobsColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? color
              : (mine ? color.withValues(alpha: 0.45) : JobsColors.border),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: highlighted
                  ? color.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: highlighted ? 10 : 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (mine) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(context.tr('jobs_card_mine'),
                    style: TextStyle(
                        fontSize: AppText.labelTiny,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
              const SizedBox(width: 6),
            ],
            if (ad.isUrgent) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: JobsColors.urgentSoft,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(context.tr('home_jobs_badge_urgent'),
                    style: const TextStyle(
                        fontSize: AppText.labelTiny,
                        fontWeight: FontWeight.w700,
                        color: JobsColors.urgent)),
              ),
            ],
            const Spacer(),
            if (ad.postedDateLabel.isNotEmpty)
              Text(
                ad.postedDateLabel,
                style: const TextStyle(
                  fontSize: AppText.labelTiny,
                  fontWeight: FontWeight.w600,
                  color: JobsColors.muted,
                ),
              ),
            // Эга/админ учун таҳрирлаш — пастдаги тугмада (бир иш = бир тугма).
            // Бошқаларга — шикоят; тегиш майдони 48dp.
            if (!canEdit)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: context.tr('ad_report_title'),
                icon: const Icon(Icons.flag_outlined,
                    size: 20, color: JobsColors.muted),
                onPressed: () => _report(context),
              ),
          ]),
          const SizedBox(height: 6),
          // Матн босилса тўлиқ очилади/йиғилади.
          InkWell(
            onTap: long ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headline,
                  style: const TextStyle(
                      fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: JobsColors.ink),
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
                if (_subline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _subline,
                    style: const TextStyle(
                        fontSize: AppText.bodyMedium,
                        height: 1.4,
                        color: Color(0xFF4A5560)),
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ],
                if (long)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.tr(_expanded
                          ? 'jobs_card_collapse'
                          : 'jobs_card_expand'),
                      style: TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ),
              ],
            ),
          ),
          if (ad.priceText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: JobsColors.priceBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ad.priceText,
                style: const TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _AreaLine(ad: ad)),
            const SizedBox(width: 8),
            if (linkedClip != null) ...[
              Tooltip(
                message: context.tr('link_video_open'),
                child: Material(
                  color: JobsColors.fieldFill,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => TvClipLink.open(context, linkedClip),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.play_circle_outline_rounded,
                          size: 18, color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Material(
              // Таҳрирлаш / Қўнғироқ — иккала табда ҳам бир хил кўк CTA.
              color: canEdit ? JobsColors.accentBlue : color,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => canEdit ? _edit(context) : _call(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      canEdit ? Icons.edit : Icons.call,
                      color: JobsColors.onBar,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      context.tr(canEdit ? 'jobs_card_edit' : 'jobs_card_call'),
                      style: const TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: JobsColors.onBar),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Эълон ҳудуди (туман) фойдаланувчи тилида. Хом `address` кўрсатилмайди:
/// эски эълонларда у эганинг профилидаги УЙ манзили эди (аудит B6, PII).
class _AreaLine extends StatelessWidget {
  const _AreaLine({required this.ad});

  final JobAd ad;

  @override
  Widget build(BuildContext context) {
    if (ad.districtId.isEmpty && ad.regionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final lang = context.contentLang;
    return ValueListenableBuilder<int>(
      valueListenable: GeoNames.revision,
      builder: (context, _, __) {
        final name = ad.districtId.isNotEmpty
            ? GeoNames.district(ad.districtId, lang)
            : GeoNames.region(ad.regionId, lang);
        if (name.trim().isEmpty) return const SizedBox.shrink();
        return Row(children: [
          const Icon(Icons.location_on, size: 14, color: JobsColors.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              style: const TextStyle(
                  fontSize: AppText.labelSmall, color: JobsColors.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]);
      },
    );
  }
}
