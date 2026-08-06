import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../controllers/jobs_controller.dart';
import '../jobs_colors.dart';
import 'complaint_sheet.dart';

/// Эълонлар (mini-OLX) рўйхатидаги бир карта.
class AdCard extends StatelessWidget {
  const AdCard({
    super.key,
    required this.ad,
  });

  final JobAd ad;

  Color get _kindColor => JobsColors.accentFor(ad.kind);

  Future<void> _call(BuildContext context) async {
    if (ad.authorPhone.isEmpty || phoneDigits(ad.authorPhone).length < 9) return;
    final url = Uri.parse('tel:${phoneForCall(ad.authorPhone)}');
    final messenger = ScaffoldMessenger.of(context);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Телефон: ${ad.authorPhone}'),
        backgroundColor: _kindColor,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
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
          ? 'Шикоят юборилди'
          : (result.error ?? 'Хатолик')),
      backgroundColor:
          result.success ? JobsColors.bar : JobsColors.urgent,
      behavior: SnackBarBehavior.floating,
    ));
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
    final color = _kindColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JobsColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JobsColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (ad.isUrgent) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: JobsColors.urgentSoft,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Шошилинч',
                    style: TextStyle(
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
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Шикоят',
              icon: const Icon(Icons.flag_outlined,
                  size: 18, color: JobsColors.muted),
              onPressed: () => _report(context),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            _headline,
            style: const TextStyle(
                fontSize: AppText.bodyLarge,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: JobsColors.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (_subline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _subline,
              style: const TextStyle(
                  fontSize: AppText.bodyMedium,
                  height: 1.4,
                  color: Color(0xFF4A5560)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
                  color: JobsColors.priceText,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Row(children: [
                const Icon(Icons.location_on,
                    size: 14, color: JobsColors.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    ad.address.isEmpty ? 'Манзил кўрсатилмаган' : ad.address,
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: ad.address.isEmpty
                            ? JobsColors.hint
                            : JobsColors.muted,
                        fontStyle: ad.address.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Material(
              color: color,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _call(context),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.call, color: JobsColors.onBar, size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Қўнғироқ',
                      style: TextStyle(
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
