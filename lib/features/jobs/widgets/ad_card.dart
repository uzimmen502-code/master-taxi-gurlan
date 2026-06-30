import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Эълонлар (mini-OLX) рўйхатидаги бир карта.
class AdCard extends StatelessWidget {
  const AdCard({
    super.key,
    required this.ad,
  });

  final JobAd ad;

  Color get _kindColor {
    switch (ad.kind) {
      case AdKind.work:
        return const Color(0xFFD84315);
      case AdKind.service:
        return AppColors.primary;
      case AdKind.ad:
        return AppColors.primary;
      case AdKind.sell:
        return AppColors.primary;
    }
  }

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

  String get _body => ad.isSell ? ad.displayText : ad.text;

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
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
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('🚨 Шошилинч',
                    style: TextStyle(
                        fontSize: AppText.labelTiny,
                        fontWeight: FontWeight.w700,
                        color: Colors.red)),
              ),
            ],
            const Spacer(),
            if (ad.postedDateLabel.isNotEmpty)
              Text(
                ad.postedDateLabel,
                style: TextStyle(
                  fontSize: AppText.labelTiny,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            _headline,
            style: const TextStyle(
                fontSize: AppText.bodyLarge,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: Colors.black87),
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
                  color: Colors.black54),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (ad.priceText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '💰 ${ad.priceText}',
                style: const TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Row(children: [
                Icon(Icons.location_on,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    ad.address.isEmpty ? 'Манзил кўрсатилмаган' : ad.address,
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: ad.address.isEmpty
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
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
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.call, color: Colors.white, size: 8),
                    SizedBox(width: 3),
                    Text(
                      'Қўнғироқ',
                      style: TextStyle(
                          fontSize: AppText.labelTiny,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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
