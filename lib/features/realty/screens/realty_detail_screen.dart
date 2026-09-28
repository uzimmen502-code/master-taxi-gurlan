import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// Битта объект карточкаси — матн, расмлар, харитадаги нуқтага ўтиш ва
/// мурожаат.
///
/// Мурожаат усулини мулк эгаси танлаган (3-бўлим): ўзига қўнғироқ ёки
/// AVA риэлторлик хизмати. Экран шу танловга бўйсунади, ўзи қарор
/// қилмайди.
class RealtyDetailScreen extends StatelessWidget {
  const RealtyDetailScreen({super.key, required this.listing});

  final RealtyListing listing;

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      'geo:${listing.lat},${listing.lng}?q=${listing.lat},${listing.lng}',
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
    final tierColor = RealtyTabs.colorFor(listing.tier);
    final specs = listing.specsLabel;
    final isAgent = listing.contactMode == RealtyContactMode.avaAgent;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_detail_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (listing.imageUrls.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: listing.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    listing.imageUrls[i],
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
          if (listing.imageUrls.isNotEmpty) const SizedBox(height: 14),

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
                  context.tr(RealtyTabs.labelKey(listing.tier)),
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
                  listing.deal == RealtyDeal.sale
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
            listing.titleOrText,
            style: TextStyle(
              fontSize: AppText.titleLarge,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          if (listing.priceText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              listing.priceText,
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

          if (listing.text.trim().isNotEmpty)
            Text(
              listing.text,
              style: TextStyle(
                fontSize: AppText.bodyLarge,
                height: 1.5,
                color: c.ink,
              ),
            ),
          const SizedBox(height: 18),

          // Матнли манзил — харидорга қўшимча аниқлик учун; аниқ жой
          // барибир харитадаги нуқта (7-бўлим).
          if (listing.addressText.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 18, color: c.ink3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    listing.addressText,
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
          OutlinedButton.icon(
            onPressed: _openInMaps,
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
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: () => callPhone(listing.contactPhone),
            icon: Icon(isAgent ? Icons.support_agent : Icons.call),
            style: ElevatedButton.styleFrom(
              backgroundColor: tierColor,
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
          ),
        ),
      ),
    );
  }
}
