import 'package:flutter/material.dart';

import '../../../../utils/app_theme.dart';
import '../../../../utils/gurlan_places.dart';

/// MFY tanlash uchun matn maydoni + suggestions dropdown.
///
/// `value` — joriy tanlangan MFY (placeholder o'rniga ko'rsatiladi).
/// `show` — dropdown ko'rinishini boshqaradigan bayroq.
class MfyDropdown extends StatelessWidget {
  const MfyDropdown({
    super.key,
    required this.ctrl,
    required this.hint,
    required this.value,
    required this.show,
    required this.icon,
    required this.iconColor,
    required this.onQueryChanged,
    required this.onSelected,
  });

  final TextEditingController ctrl;
  final String hint;
  final String value;
  final bool show;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelected;

  static const Color _blue = Color(0xFF0288D1);

  @override
  Widget build(BuildContext context) {
    final suggestions = GurlanPlaces.search(ctrl.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: TextField(
          controller: ctrl,
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: value.isNotEmpty ? value : hint,
            hintStyle: TextStyle(
                color: value.isNotEmpty ? Colors.black87 : Colors.grey.shade400,
                fontSize: AppText.bodyMedium),
            prefixIcon: Icon(icon, color: iconColor, size: 18),
            suffixIcon: value.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: () {
                      ctrl.clear();
                      onSelected('');
                    },
                  )
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
      if (show && suggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)
              ]),
          child: Column(
            children: suggestions
                .map((p) => InkWell(
                      onTap: () => onSelected(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.location_on,
                              size: 13, color: _blue),
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
