import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Kuryer paneli AppBar tugmasi — online/offline holatini almashtiradi.
class CourierOnlineToggle extends StatelessWidget {
  const CourierOnlineToggle({
    super.key,
    required this.isOnline,
    required this.onToggle,
  });

  final bool isOnline;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOnline ? AppColors.primaryMid : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isOnline
                ? context.tr('courier_info_online')
                : context.tr('courier_info_offline'),
            style: TextStyle(
                fontSize: 12,
                color: isOnline ? AppColors.onPrimary : Colors.white,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
