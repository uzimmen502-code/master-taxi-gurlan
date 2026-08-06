import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../../jobs/jobs_colors.dart';

/// Бош экран — ИШ ЭЪЛОН қисқа превью (маҳсулот лентасидан кейин).
class HomeJobsPreviewSection extends StatelessWidget {
  const HomeJobsPreviewSection({
    super.key,
    required this.onOpenBoard,
  });

  /// «Барчаси» ва қатор босиш → ИШ ЭЪЛОН экрани.
  final VoidCallback onOpenBoard;

  static const int maxItems = 8;

  List<JobAd> _pickPreview(List<JobAd> raw) {
    final list = raw.where((a) => !a.isExpired).toList(growable: false);
    final urgent = <JobAd>[];
    final regular = <JobAd>[];
    for (final a in list) {
      if (a.supportsUrgent && a.isUrgent) {
        urgent.add(a);
      } else {
        regular.add(a);
      }
    }
    int byNewest(JobAd a, JobAd b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    }

    urgent.sort(byNewest);
    regular.sort(byNewest);
    return [...urgent, ...regular].take(maxItems).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<JobAd>>(
      stream: context.read<JobsRepository>().watchAllActive(limit: 80),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const SizedBox.shrink();
        }
        final items = _pickPreview(snap.data ?? const <JobAd>[]);
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('home_module_jobs'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: JobsColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenBoard,
                  style: TextButton.styleFrom(
                    foregroundColor: JobsColors.bar,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.tr('home_jobs_preview_see_all'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: AppText.labelSmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (ad) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _JobsPreviewTile(ad: ad, onTap: onOpenBoard),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JobsPreviewTile extends StatelessWidget {
  const _JobsPreviewTile({required this.ad, required this.onTap});

  final JobAd ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = JobsColors.accentFor(ad.kind);
    final headline = ad.titleOrText.trim();
    final showUrgent = ad.supportsUrgent && ad.isUrgent;

    return Material(
      color: JobsColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JobsColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 42,
                decoration: BoxDecoration(
                  color: showUrgent ? JobsColors.urgent : accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showUrgent) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: JobsColors.urgentSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          context.tr('home_jobs_badge_urgent'),
                          style: const TextStyle(
                            fontSize: AppText.labelTiny,
                            fontWeight: FontWeight.w800,
                            color: JobsColors.urgent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: JobsColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (ad.priceText.trim().isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              ad.priceText.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppText.labelTiny,
                                fontWeight: FontWeight.w700,
                                color: JobsColors.priceText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (ad.address.trim().isNotEmpty)
                          Flexible(
                            child: Text(
                              ad.address.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppText.labelTiny,
                                color: JobsColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: JobsColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
