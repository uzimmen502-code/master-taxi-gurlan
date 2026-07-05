import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Route card ichidagi MFY qatori — bosilganda picker ochiladi.
class MarshrutRouteField extends StatelessWidget {
  const MarshrutRouteField({
    super.key,
    required this.hint,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.onClear,
  });

  final String hint;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? value : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.bodyMedium,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                  color: hasValue ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
            if (hasValue && onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}
