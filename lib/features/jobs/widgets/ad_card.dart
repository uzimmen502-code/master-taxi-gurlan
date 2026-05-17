import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/job_ad.dart';
import '../../../utils/app_theme.dart';

/// Эълонлар (mini-OLX) рўйхатидаги бир карта.
///
/// UX қарорлар (Phase 5):
///   - "X кун қолди" badge **олиб ташланди** — фойдаланувчига муҳим эмас.
///   - Сарлавҳа + матн ажратилди (агар title бўш бўлса — матн title бўлади).
///   - **Қўнғироқ тугмаси катта** ва ўнг ёнда — энг муҳим CTA.
///   - Шошилинч badge фақат `work` учун, кичикроқ.
///   - Манзил аниқ кўринади (location icon + matn).
///   - Тип ранги — кенг maydoni emas, фақат top-left small badge.
class AdCard extends StatelessWidget {
  const AdCard({
    super.key,
    required this.ad,
    required this.canEdit,
    required this.onEdit,
    required this.onComplain,
  });

  final JobAd ad;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onComplain;

  Color get _kindColor {
    switch (ad.kind) {
      case AdKind.work:
        return const Color(0xFFD84315); // тўқ-қизғиш
      case AdKind.service:
        return const Color(0xFF6A1B9A); // бинафша
      case AdKind.ad:
        return const Color(0xFF0277BD); // кўк
    }
  }

  Future<void> _call(BuildContext context) async {
    if (ad.authorPhone.isEmpty) return;
    final cleaned = ad.authorPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri(scheme: 'tel', path: cleaned);
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

  String get _headline {
    if (ad.title.trim().isNotEmpty) return ad.title;
    return ad.text;
  }

  String get _subline {
    if (ad.title.trim().isEmpty) return '';
    return ad.text;
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row: urgent (work uchun) + time + edit/complain.
          // Kind label badge olib tashlandi — tab allaqachon kindni ko'rsatib turibdi,
          // ortiqcha "Иш бор / Хизмат / Эълон" matnini takrorlash shart emas.
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
            Text(ad.timeAgo,
                style: TextStyle(
                    fontSize: AppText.labelTiny, color: Colors.grey.shade500)),
            if (canEdit) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.edit, size: 16, color: color),
                ),
              ),
            ],
            InkWell(
              onTap: onComplain,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert,
                    size: 16, color: Colors.grey.shade400),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Headline (title yoki matn).
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
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Bottom row: address (left, takes space) + Call button (right).
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
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _call(context),
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.call, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Қўнғироқ',
                      style: TextStyle(
                          fontSize: AppText.bodySmall,
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
