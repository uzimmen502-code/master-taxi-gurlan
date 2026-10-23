import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/map_launcher.dart';
import '../../ev_charging/screens/ev_charging_map_screen.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../restaurants/screens/restaurant_screen.dart';
import '../domain/business_pin.dart';

/// Нуқта босилганда чиқадиган тўлиқ маълумот варағи (эга қарори: «танлаб босилганда тўлиқ маълумот»).
///
/// Матн фақат берилган майдонларни кўрсатади (бўш қатор йўқ). Кафе ва зарядка станцияси учун
/// ўз экранини очиш тугмаси бор; улгуржи сотувчи ва оддий объектда — қўнғироқ ва йўналиш.
class BusinessDetailSheet extends StatelessWidget {
  const BusinessDetailSheet({super.key, required this.pin});

  final BusinessPin pin;

  static Future<void> show(BuildContext context, BusinessPin pin) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => BusinessDetailSheet(pin: pin),
    );
  }

  Future<void> _call(BuildContext context) async {
    final digits = pin.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('tel:${digits.startsWith('+') ? digits : '+$digits'}');
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('bizmap_err_generic'))));
    }
  }

  Future<void> _openWebsite() async {
    final raw = pin.website.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final origin = pin.origin;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(pin.category.icon, size: 20, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr(pin.category.labelKey),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(pin.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (pin.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(pin.subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 14),
            if (pin.description.isNotEmpty)
              _Line(icon: Icons.notes_rounded, text: pin.description),
            if (pin.address.isNotEmpty)
              _Line(icon: Icons.place_outlined, text: pin.address),
            if (pin.hours.isNotEmpty)
              _Line(icon: Icons.schedule_rounded, text: pin.hours),
            if (pin.phone.isNotEmpty)
              _Line(icon: Icons.phone_outlined, text: pin.phone, onTap: () => _call(context)),
            if (pin.website.isNotEmpty)
              _Line(icon: Icons.public_rounded, text: pin.website, onTap: _openWebsite),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pin.phone.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(context.tr('bizmap_call')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openMapsNavigation(lat: pin.lat, lng: pin.lng, label: pin.name),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: Text(context.tr('bizmap_route')),
                ),
                if (origin is Restaurant)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => RestaurantScreen(restaurant: origin)),
                      );
                    },
                    icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                    label: Text(context.tr('bizmap_open_menu')),
                  ),
                if (pin.source == BusinessSource.evStation)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const EvChargingMapScreen()),
                      );
                    },
                    icon: const Icon(Icons.ev_station_rounded, size: 18),
                    label: Text(context.tr('bizmap_open_ev')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: onTap == null ? null : AppColors.primaryDark,
                decoration: onTap == null ? null : TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
