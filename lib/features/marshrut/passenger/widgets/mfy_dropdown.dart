import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../utils/gurlan_places.dart';

/// MFY tanlash uchun matn maydoni + suggestions dropdown.
///
/// `value` — joriy tanlangan MFY (placeholder o'rniga ko'rsatiladi).
/// `show` — dropdown ko'rinishini boshqaradigan bayroq.
/// [recentPlaces] — SharedPreferences dan oxirgi MFY lar (tavsiya).
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
    this.recentPlaces = const [],
    this.onTap,
    this.compact = false,
  });

  final TextEditingController ctrl;
  final String hint;
  final String value;
  final bool show;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelected;
  final List<String> recentPlaces;
  final VoidCallback? onTap;
  final bool compact;

  static const Color _blue = AppColors.primary;

  List<String> _suggestions() {
    final q = ctrl.text.trim();
    final recent = recentPlaces
        .where(
          (p) => q.isEmpty || p.toLowerCase().contains(q.toLowerCase()),
        )
        .toList();
    if (q.length >= 2) {
      final places = GurlanPlaces.search(ctrl.text);
      final seen = <String>{};
      final merged = <String>[];
      for (final p in recent) {
        if (seen.add(p)) merged.add(p);
      }
      for (final p in places) {
        if (seen.add(p)) merged.add(p);
      }
      return merged;
    }
    return recent;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions();
    final recentSet = recentPlaces.toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (compact)
        TextField(
          controller: ctrl,
          onChanged: onQueryChanged,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: iconColor, size: 20),
            suffixIcon: value.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: () {
                      ctrl.clear();
                      onSelected('');
                    },
                  )
                : null,
            border: InputBorder.none,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          ),
          style: TextStyle(
            fontSize: AppText.bodyMedium,
            fontWeight: value.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
            color: value.isNotEmpty ? Colors.black87 : Colors.grey.shade600,
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: ctrl,
            onChanged: onQueryChanged,
            onTap: onTap,
            decoration: InputDecoration(
              hintText: value.isNotEmpty ? value : hint,
              hintStyle: TextStyle(
                  color: value.isNotEmpty
                      ? Colors.black87
                      : Colors.grey.shade400,
                  fontSize: AppText.bodyMedium),
              prefixIcon: Icon(icon, color: iconColor, size: 18),
              suffixIcon: value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: Colors.grey),
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
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)
              ]),
          child: Column(
            children: suggestions
                .map((p) => InkWell(
                      onTap: () => onSelected(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Icon(
                            recentSet.contains(p)
                                ? Icons.history
                                : Icons.location_on,
                            size: 13,
                            color: recentSet.contains(p)
                                ? Colors.grey.shade600
                                : _blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p,
                                style: const TextStyle(
                                    fontSize: AppText.bodyMedium)),
                          ),
                        ]),
                      ),
                    ))
                .toList(),
          ),
        ),
    ]);
  }
}
