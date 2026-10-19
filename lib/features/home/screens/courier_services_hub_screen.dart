import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/service_spotlight_item.dart';

const _bg = AppColors.lime;
const _titleDark = AppColors.primaryText;
const _brandGreen = AppColors.limeDeep;
const _cardBorder = AppColors.cardBorderMuted;

/// Hub kartasidagi sarlavha / izoh kalitlari (`moduleId` bo'yicha). Sarlavha
/// kaliti bo'lmasa — xizmatning bosh sahifadagi nomi (`ServiceSpotlightItem.label`).
const _hubTexts = <String, ({String? title, String subtitle})>{
  'bread': (
    title: 'courier_hub_bread_title',
    subtitle: 'courier_hub_bread_subtitle'
  ),
  'carpet_wash': (
    title: 'courier_hub_carpet_title',
    subtitle: 'courier_hub_carpet_subtitle'
  ),
  'restaurants': (title: null, subtitle: 'courier_hub_restaurants_subtitle'),
  'milk': (title: null, subtitle: 'courier_hub_milk_subtitle'),
};

/// Kuryer xizmati — kuryer ulangan BARCHA xizmatlar (ega, 2026-10-19). Ro'yxatni
/// `courierConnectedServices` (home_services_catalog.dart) tuzadi: bosh sahifada
/// ko'rinadigan va kuryer ishlaydigan xizmatlar; karta bosilsa xizmatning o'z
/// kirish mantig'i ishlaydi (ruxsat, "tez kunda" va h.k.).
class CourierServicesHubScreen extends StatelessWidget {
  const CourierServicesHubScreen({super.key, required this.items});

  final List<ServiceSpotlightItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(context.tr('courier_hub_title')),
        backgroundColor: _brandGreen,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            context.tr('courier_hub_subtitle'),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items) ...[
            _ServiceCard(
              key: ValueKey('courier-hub-${item.moduleId}'),
              imagePath: item.imagePath,
              title: _hubTexts[item.moduleId]?.title != null
                  ? context.tr(_hubTexts[item.moduleId]!.title!)
                  : item.label,
              subtitle: _hubTexts[item.moduleId] != null
                  ? context.tr(_hubTexts[item.moduleId]!.subtitle)
                  : '',
              onTap: item.onTap,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    super.key,
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String? imagePath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imagePath == null
                    ? const SizedBox(width: 56, height: 56)
                    : Image.asset(
                        imagePath!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _titleDark,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
