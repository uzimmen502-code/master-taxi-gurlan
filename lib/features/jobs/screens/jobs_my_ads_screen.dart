import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/job_ad.dart';
import '../controllers/jobs_controller.dart';
import '../jobs_colors.dart';
import '../jobs_sections.dart';
import '../widgets/ad_card.dart';

/// «Менинг эълонларим» — эганинг ҲАМ ЭЪЛОНЛАРИ, ҲАР ҚАНДАЙ статусда.
///
/// Аудит A2 (2026-10-18). Symptom: эълон модерацияга юборилгач («текширувга
/// юборилди») фойдаланувчи уни ҳеч қаерда кўрмасди — умумий лента фақат
/// `active`ни кўрсатади, `watchMyAds()` эса ҳеч бир экранда ишлатилмаган.
/// Фойдаланувчи эълони йўқолган деб ўйлаб қайта жойлайверарди (кунига
/// 10 лимитни еб). Fix: ҳолат белгиси билан шахсий рўйхат.
class JobsMyAdsScreen extends StatefulWidget {
  const JobsMyAdsScreen({super.key, this.stream});

  /// Тестлар учун: берилса, контроллер оқими ўрнига шу ишлатилади.
  final Stream<List<JobAd>>? stream;

  @override
  State<JobsMyAdsScreen> createState() => _JobsMyAdsScreenState();
}

class _JobsMyAdsScreenState extends State<JobsMyAdsScreen> {
  late Stream<List<JobAd>> _stream;

  Stream<List<JobAd>> _open() =>
      widget.stream ?? context.read<JobsController>().watchMyAds();

  @override
  void initState() {
    super.initState();
    _stream = _open();
  }

  void _retry() => setState(() => _stream = _open());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsColors.scaffold,
      appBar: AppBar(
        title: Text(
          context.tr('jobs_my_ads'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: JobsColors.bar,
        foregroundColor: JobsColors.onBar,
        elevation: 0,
      ),
      body: StreamBuilder<List<JobAd>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('[JobsMyAds] ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('jobs_load_error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: JobsColors.muted)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _retry,
                    child: Text(context.tr('home_section_retry')),
                  ),
                ]),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ads = snap.data!;
          if (ads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  context.tr('jobs_my_ads_empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: JobsColors.ink),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
            itemCount: ads.length,
            itemBuilder: (_, i) => _MyAdTile(ad: ads[i]),
          );
        },
      ),
    );
  }
}

/// Карточка + ҳолат белгиси (текширувда / фаол / ёпилган / рад этилган).
class _MyAdTile extends StatelessWidget {
  const _MyAdTile({required this.ad});

  final JobAd ad;

  @override
  Widget build(BuildContext context) {
    final expired = ad.isExpired;
    final pending = ad.status == 'pending';
    final blocked = ad.status == 'blocked';
    final live = ad.status == 'active' && !expired;
    final color = live
        ? JobsColors.accentFor(ad.kind)
        : (blocked ? JobsColors.urgent : JobsColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                context.tr(JobsSections.statusKeyFor(ad.status, expired: expired)),
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
            ),
            if (pending) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('jobs_my_ads_pending_hint'),
                  style: const TextStyle(
                      fontSize: AppText.labelTiny, color: JobsColors.muted),
                ),
              ),
            ],
          ]),
        ),
        AdCard(ad: ad),
      ],
    );
  }
}

/// «Менинг эълонларим»ни очиш — [controller] бўлим экрани билан умумий.
Future<void> pushJobsMyAds(NavigatorState navigator, JobsController controller) {
  return navigator.push(MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider<JobsController>.value(
      value: controller,
      child: const JobsMyAdsScreen(),
    ),
  ));
}

Future<void> openJobsMyAds(BuildContext context, JobsController controller) =>
    pushJobsMyAds(Navigator.of(context), controller);
