import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/job_ad.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../domain/job_vacancy.dart';

/// Вакансия тафсилоти: лавозим, иш берувчи, маош, иш тартиби, тажриба, ҳудуд, «Талаблар» ва «Ариза бериш»
/// (эга 2026-11-28): ариза — мавжуд «Буюртма ёзиш» чати (`openDealChat` source `vacancy`), телефон кўрсатилмайди.
class VacancyDetailScreen extends StatefulWidget {
  const VacancyDetailScreen({super.key, required this.ad, this.myUid, this.onApply, this.onOpenEmployer});

  final JobAd ad;

  /// Тест учун (сукут — жорий фойдаланувчи телефони).
  @visibleForTesting
  final String? myUid;

  /// Тест учун: «Ариза бериш» ([openDealChatFlow] ўрнига).
  @visibleForTesting
  final Future<void> Function(BuildContext context, JobAd ad)? onApply;

  /// Иш берувчи (завод) номи босилганда — завод саҳифаси (чақирувчи беради; йўқ бўлса номи оддий матн).
  final void Function(BuildContext context, JobVacancy vacancy)? onOpenEmployer;

  @override
  State<VacancyDetailScreen> createState() => _VacancyDetailScreenState();
}

class _VacancyDetailScreenState extends State<VacancyDetailScreen> {
  late final String _me =
      widget.myUid ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  bool _busy = false;

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final custom = widget.onApply;
      if (custom != null) {
        await custom(context, widget.ad);
      } else {
        await openDealChatFlow(context,
            productId: widget.ad.id, myUid: _me, source: DealChatSource.vacancy, draft: context.tr('vac_apply_draft'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final ad = widget.ad;
    final v = ad.vacancy!;
    final district = GeoNames.district(ad.districtId, context.contentLang, fallback: ad.address);
    final canApply = dealChatShowWrite(myUid: _me, ownerPhone: ad.authorPhone);
    Widget row(String labelKey, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(context.tr(labelKey), style: TextStyle(color: c.ink2))),
            Expanded(child: Text(value, key: key, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600))),
          ]),
        );
    final employer = widget.onOpenEmployer;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('vac_detail_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(v.position, key: const ValueKey('vac_detail_position'), style: AvaText.homeSectionTitle.copyWith(color: c.ink)),
          if (v.employerName.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: employer == null ? null : () => employer(context, v),
              child: Text(
                v.employerName,
                key: const ValueKey('vac_detail_employer'),
                style: TextStyle(color: employer == null ? c.ink2 : c.brandText, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 16),
          row('vac_field_salary', v.salaryLabel(context.tr), key: const ValueKey('vac_detail_salary')),
          if (v.schedule.isNotEmpty) row('vac_field_schedule', context.tr(JobVacancy.scheduleKey(v.schedule))),
          if (v.experience.isNotEmpty) row('vac_field_experience', context.tr(JobVacancy.experienceKey(v.experience))),
          if (district.isNotEmpty) row('vac_field_district', district),
          const SizedBox(height: 8),
          Text(context.tr('vac_field_requirements'), style: AvaText.homeCardTitle.copyWith(color: c.ink)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AvaRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Text(v.requirements, key: const ValueKey('vac_detail_requirements')),
          ),
          if (ad.text.trim().isNotEmpty && ad.text.trim() != v.requirements) ...[
            const SizedBox(height: 16),
            Text(context.tr('vac_field_description'), style: AvaText.homeCardTitle.copyWith(color: c.ink)),
            const SizedBox(height: 6),
            Text(ad.text.trim()),
          ],
          if (ad.postedDateLabel.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${context.tr('vac_posted')}: ${ad.postedDateLabel}', style: TextStyle(color: c.ink3, fontSize: 12)),
          ],
        ],
      ),
      bottomNavigationBar: canApply
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                key: const ValueKey('vac_apply'),
                onPressed: _busy ? null : _apply,
                icon: const Icon(Icons.send_rounded),
                label: Text(context.tr('vac_apply')),
              ),
            )
          : null,
    );
  }
}
