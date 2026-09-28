import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_package_sheet.dart';
import '../widgets/realty_video_sheet.dart';

/// Битта объект карточкаси.
///
/// ПЕЙВОЛЛ шу ерда: тавсиф, расм ва тахминий ҳудуд ҳаммага очиқ, аниқ
/// координата ва алоқа рақами эса ахборот пакетидан очилгандан кейин
/// кўринади (концепция, 4 ва 9-бўлимлар).
///
/// Муҳими: ёпиқ маълумот иловага УМУМАН келмайди — у Firestore қоидаси
/// билан тўсилган алоҳида ҳужжатда. Яъни бу экран маълумотни яшириб
/// турмайди, унга эга эмас.
class RealtyDetailScreen extends StatefulWidget {
  const RealtyDetailScreen({super.key, required this.listing});

  final RealtyListing listing;

  @override
  State<RealtyDetailScreen> createState() => _RealtyDetailScreenState();
}

class _RealtyDetailScreenState extends State<RealtyDetailScreen> {
  final _repo = RealtyRepository();

  RealtyDetail? _detail;
  bool _loading = true;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// Эга ва очган харидор учун маълумот келади, қолганига `null`.
  Future<void> _loadDetail() async {
    final detail = await _repo.fetchDetail(widget.listing.id);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  Future<void> _unlock() async {
    setState(() => _unlocking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.unlockListing(widget.listing.id);
      await _loadDetail();
      if (!mounted) return;
      setState(() => _unlocking = false);
    } on RealtyException catch (e) {
      if (!mounted) return;
      setState(() => _unlocking = false);
      if (e.code == 'no_unlocks_left') {
        // Пакет йўқ — дарҳол сотиб олиш варағини очамиз.
        final bought = await showRealtyPackageSheet(context);
        if (bought && mounted) await _unlock();
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_error_generic')),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _openInMaps(RealtyDetail detail) async {
    final uri = Uri.parse(
      'geo:${detail.lat},${detail.lng}?q=${detail.lat},${detail.lng}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Харита иловаси йўқ — жимгина ўтказиб юборамиз.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = widget.listing;
    final tierColor = RealtyTabs.colorFor(r.tier);
    final specs = r.specsLabel;
    final detail = _detail;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_detail_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (r.imageUrls.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: r.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    r.imageUrls[i],
                    width: 280,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 280,
                      color: c.surface2,
                    ),
                  ),
                ),
              ),
            ),
          if (r.imageUrls.isNotEmpty) const SizedBox(height: 14),

          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.tr(RealtyTabs.labelKey(r.tier)),
                  style: const TextStyle(
                    fontSize: AppText.labelTiny,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.tr(
                  r.deal == RealtyDeal.sale
                      ? 'realty_deal_sale'
                      : 'realty_deal_rent',
                ),
                style: TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: c.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            r.titleOrText,
            style: TextStyle(
              fontSize: AppText.titleLarge,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          if (r.priceText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.priceText,
              style: TextStyle(
                fontSize: AppText.titleMedium,
                fontWeight: FontWeight.w700,
                color: tierColor,
              ),
            ),
          ],
          if (specs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              specs,
              style: TextStyle(fontSize: AppText.bodyMedium, color: c.ink2),
            ),
          ],
          const SizedBox(height: 14),

          if (r.text.trim().isNotEmpty)
            Text(
              r.text,
              style: TextStyle(
                fontSize: AppText.bodyLarge,
                height: 1.5,
                color: c.ink,
              ),
            ),
          const SizedBox(height: 14),

          // «Видеони кўриш» — фақат эга видео боғлаган бўлса (3-бўлим).
          // Видео БЕПУЛ кўрилади: ахборот пакети аниқ манзил ва алоқа
          // учун, видео учун эмас.
          if (r.hasVideo) ...[
            OutlinedButton.icon(
              onPressed: () => openRealtyVideo(context, clipId: r.videoClipId),
              icon: const Icon(Icons.play_circle_outline, size: 20),
              style: OutlinedButton.styleFrom(
                foregroundColor: tierColor,
                side: BorderSide(color: tierColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(context.tr('realty_watch_video')),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 4),

          if (r.addressText.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 18, color: c.ink3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.addressText,
                    style: TextStyle(
                      fontSize: AppText.bodyMedium,
                      color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (detail != null)
            OutlinedButton.icon(
              onPressed: () => _openInMaps(detail),
              icon: const Icon(Icons.map_outlined, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.line),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(context.tr('realty_open_on_map')),
            )
          else
            _LockedPanel(unlocksLeft: _repo.watchUnlocksLeft()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _loading
              ? const SizedBox(height: 48)
              : detail != null
                  ? _ContactButton(
                      listing: r,
                      detail: detail,
                      color: tierColor,
                    )
                  : ElevatedButton.icon(
                      onPressed: _unlocking ? null : _unlock,
                      icon: _unlocking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_open),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tierColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: Text(
                        context.tr('realty_unlock_cta'),
                        style: const TextStyle(
                          fontSize: AppText.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

/// Ёпиқ маълумот тушунтириши — нима беркитилгани ва нега.
class _LockedPanel extends StatelessWidget {
  const _LockedPanel({required this.unlocksLeft});

  final Stream<int> unlocksLeft;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: c.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('realty_locked_title'),
                  style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('realty_locked_body'),
            style: TextStyle(fontSize: AppText.bodySmall, color: c.ink2),
          ),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: unlocksLeft,
            builder: (context, snap) {
              final left = snap.data ?? 0;
              return Text(
                '${context.tr('realty_unlocks_left')}: $left',
                style: TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: left > 0 ? c.brand : c.ink3,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.listing,
    required this.detail,
    required this.color,
  });

  final RealtyListing listing;
  final RealtyDetail detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isAgent = listing.contactMode == RealtyContactMode.avaAgent;
    return ElevatedButton.icon(
      onPressed: () => callPhone(detail.contactPhone(listing.contactMode)),
      icon: Icon(isAgent ? Icons.support_agent : Icons.call),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      label: Text(
        context.tr(
          isAgent ? 'realty_contact_agent_cta' : 'realty_contact_owner_cta',
        ),
        style: const TextStyle(
          fontSize: AppText.bodyLarge,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
