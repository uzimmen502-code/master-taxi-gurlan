import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../domain/job_vacancy.dart';
import 'vacancy_detail_screen.dart';
import 'vacancy_form_screen.dart';

/// «Иш ўринлари — Вакансиялар» (эга 2026-11-28): ФАҚАТ иш берувчи вакансиялари (`ads` type `work` + `vacancy`).
///
/// Иш қидирувчи эълонлари бу рўйхатга тушмайди: улар `ad`/`service` турида (алоҳида белгисиз) — бу экран фақат
/// сервер `vacancy` харитасини ёзган `work` ҳужжатларини кўрсатади. Ҳудуд — `jobs` модули ҳалқалари (туман →
/// вилоят → Республика), модерация ва 30 кунлик муддат — сервер.
class VacanciesScreen extends StatefulWidget {
  const VacanciesScreen({super.key, this.highlightAdId = '', this.watch});

  /// Бош саҳифа тасмасидан босилган вакансия — рўйхат бошида.
  final String highlightAdId;

  /// Тест учун оқим (сукут — Firestore).
  @visibleForTesting
  final Stream<List<JobAd>> Function(GeoScope scope)? watch;

  static const moduleId = 'jobs';

  @override
  State<VacanciesScreen> createState() => _VacanciesScreenState();
}

class _VacanciesScreenState extends State<VacanciesScreen> {
  GeoScope _scope = GeoContext.scopeFor(VacanciesScreen.moduleId);
  late Stream<List<JobAd>> _stream = _open();

  Stream<List<JobAd>> _open() => widget.watch?.call(_scope) ?? JobsRepository().watchVacancies(_scope);

  void _setScope(GeoScope s) {
    if (s == _scope) return;
    setState(() {
      _scope = s;
      _stream = _open();
    });
  }

  Future<void> _add() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const VacancyFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('vac_title')),
        actions: [
          IconButton(
            key: const ValueKey('vac_add'),
            tooltip: context.tr('vac_add'),
            icon: const Icon(Icons.add_rounded),
            onPressed: _add,
          ),
        ],
      ),
      body: Column(
        children: [
          GeoTierBar(moduleId: VacanciesScreen.moduleId, scope: _scope, onChanged: _setScope),
          Expanded(
            child: StreamBuilder<List<JobAd>>(
              stream: _stream,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  debugPrint('[Vacancies] VACANCIES_LOAD_FAILED: ${snap.error}');
                  return Center(child: Text(ctx.tr('vac_load_error'), key: const ValueKey('vac_error')));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = vacanciesWithHighlightFirst(snap.data!, widget.highlightAdId);
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(ctx.tr('vac_empty'), key: const ValueKey('vac_empty'), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        GeoWiderHint(moduleId: VacanciesScreen.moduleId, scope: _scope, onChanged: _setScope),
                      ]),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => VacancyCard(
                    ad: list[i],
                    highlighted: list[i].id == widget.highlightAdId,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => VacancyDetailScreen(ad: list[i])),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Босилган вакансия биринчи (қолган тартиб ўзгармайди).
List<JobAd> vacanciesWithHighlightFirst(List<JobAd> list, String id) {
  if (id.isEmpty) return list;
  final hit = list.where((a) => a.id == id).toList();
  if (hit.isEmpty) return list;
  return [...hit, ...list.where((a) => a.id != id)];
}

/// Вакансия карточкаси: лавозим, иш берувчи, маош, иш тартиби, ҳудуд.
class VacancyCard extends StatelessWidget {
  const VacancyCard({super.key, required this.ad, required this.onTap, this.highlighted = false});

  final JobAd ad;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final v = ad.vacancy!;
    final district = GeoNames.district(ad.districtId, context.contentLang, fallback: ad.address);
    return Material(
      key: ValueKey('vac_card_${ad.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AvaRadius.card),
        side: BorderSide(color: highlighted ? c.brand : c.line, width: highlighted ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.position, style: AvaText.homeCardTitle.copyWith(color: c.ink)),
              if (v.employerName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(v.employerName, style: TextStyle(color: c.ink2)),
              ],
              const SizedBox(height: 6),
              Text(
                v.salaryLabel(context.tr),
                key: ValueKey('vac_salary_${ad.id}'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (v.schedule.isNotEmpty) context.tr(JobVacancy.scheduleKey(v.schedule)),
                  if (district.isNotEmpty) district,
                ].join(' · '),
                style: TextStyle(color: c.ink2, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

