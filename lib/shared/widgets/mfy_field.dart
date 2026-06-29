import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../utils/gurlan_places.dart';

/// Р“СѓСЂР»Р°РЅ РњР¤Р™ С‚Р°РЅР»Р°С€ СѓС‡СѓРЅ СѓРЅРёРІРµСЂСЃР°Р» input. Driver register, driver schedule
/// РєР°Р±Рё driver flow'Р»Р°СЂРёРґР° Т›Р°Р№С‚Р° РёС€Р»Р°С‚РёР»Р°РґРё. Passenger С‚РѕРјРѕРЅРёРґР° СЃРѕРґРґР°СЂРѕТ›
/// `MfyDropdown` Р±РѕСЂ вЂ” Сѓ Р±РѕС€Т›Р°С‡Р° (yagona text field Р±РёР»Р°РЅ).
class MfyField extends StatelessWidget {
  const MfyField({
    super.key,
    required this.ctrl,
    required this.hint,
    required this.iconColor,
    required this.showSug,
    required this.query,
    required this.onChanged,
    required this.onSelected,
    required this.onClear,
  });

  final TextEditingController ctrl;
  final String hint;
  final Color iconColor;
  final bool showSug;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final suggestions = GurlanPlaces.search(query);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: ctrl.text.isNotEmpty
                  ? iconColor.withValues(alpha: 0.4)
                  : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
          ],
        ),
        child: TextField(
          controller: ctrl,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
            prefixIcon: Icon(Icons.location_on, color: iconColor, size: 18),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: onClear)
                : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),
      if (showSug && suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)
            ],
          ),
          child: Column(
            children: suggestions
                .map((p) => InkWell(
                      onTap: () => onSelected(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Icon(Icons.location_on, size: 13, color: iconColor),
                          const SizedBox(width: 8),
                          Text(p,
                              style: const TextStyle(
                                  fontSize: AppText.bodyMedium)),
                        ]),
                      ),
                    ))
                .toList(),
          ),
        ),
    ]);
  }
}
