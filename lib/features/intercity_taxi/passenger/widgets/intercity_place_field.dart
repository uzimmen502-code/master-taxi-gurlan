import 'package:flutter/material.dart';
import '../intercity_colors.dart';

import '../../../../utils/intercity_places.dart';

/// Шаҳарлараро қидирув maydoni + autokomplit (tarix + IntercityPlaces).
class IntercityPlaceField extends StatelessWidget {
  const IntercityPlaceField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.dotColor,
    required this.showSuggestions,
    required this.suggestions,
    required this.recentCanonical,
    required this.locale,
    required this.onChanged,
    required this.onSelected,
    required this.onClear,
    this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final Color dotColor;
  final bool showSuggestions;
  final List<String> suggestions;
  final List<String> recentCanonical;
  final Locale locale;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelected;
  final VoidCallback onClear;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final recentDisplay = recentCanonical
        .map((c) => IntercityPlaces.displayForLocale(c, locale))
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onTap: onTap,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle:
                        TextStyle(color: IntercityColors.textFaint, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                size: 16, color: IntercityColors.textFaint),
                            onPressed: onClear,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showSuggestions && suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 22, top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: IntercityColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: IntercityColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: IntercityColors.surfaceSoft),
              itemBuilder: (_, i) {
                final label = suggestions[i];
                final isRecent = recentDisplay.contains(label);
                return InkWell(
                  onTap: () => onSelected(label),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isRecent ? Icons.history : Icons.location_on_outlined,
                          size: 14,
                          color: isRecent
                              ? IntercityColors.textMuted
                              : dotColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
