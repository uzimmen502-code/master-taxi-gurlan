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
    this.compact = false,
  });

  final String hint;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isNotEmpty;
    final vPad = compact ? 7.0 : 10.0;
    final iconSize = compact ? 18.0 : 20.0;
    final fontSize = compact ? AppText.bodySmall : AppText.bodyMedium;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: vPad),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: iconSize),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? value : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                  color: hasValue ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
            if (hasValue && onClear != null)
              IconButton(
                onPressed: onClear,
                icon: Icon(Icons.close, size: compact ? 16 : 18, color: Colors.grey),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: compact ? 28 : 32,
                  minHeight: compact ? 28 : 32,
                ),
              )
            else
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: compact ? 18 : 20),
          ],
        ),
      ),
    );
  }
}
