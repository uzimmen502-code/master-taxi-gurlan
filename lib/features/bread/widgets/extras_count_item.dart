import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// РЎР°РІР°С‚РґР° Т›СћС€РёРјС‡Р° РјР°ТіСЃСѓР»РѕС‚ СѓС‡СѓРЅ `[-] count [+]` Т›Р°С‚РѕСЂРё (Т›Р°РґР°Рј: РґРѕРЅР° 1, РєРі/Р» 0.5).
class ExtrasCountItem extends StatelessWidget {
  const ExtrasCountItem({
    super.key,
    required this.emoji,
    required this.name,
    required this.qty,
    required this.count,
    required this.max,
    required this.qtyStep,
    required this.onDecrement,
    required this.onIncrement,
    required this.formatStepperCount,
  });

  final String emoji;
  final String name;
  final String qty;
  final num count;
  final num max;
  final num qtyStep;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final String Function(num count) formatStepperCount;

  static const _green = AppColors.primaryDark;

  bool get _canMinus => count > 1e-9;

  bool get _canPlus => count + qtyStep <= max + 1e-9;

  @override
  Widget build(BuildContext context) {
    final selected = count > 1e-9;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.scaffold : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _green : Colors.grey.shade200,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600)),
            Text(qty,
                style: TextStyle(
                    fontSize: AppText.labelTiny, color: Colors.grey.shade500)),
          ]),
        ),
        Row(children: [
          _stepperBtn(
            icon: Icons.remove,
            enabled: _canMinus,
            onTap: onDecrement,
          ),
          Container(
            width: 56,
            alignment: Alignment.center,
            child: Text(
              formatStepperCount(count),
              style: TextStyle(
                fontSize: AppText.bodySmall,
                fontWeight: FontWeight.bold,
                color: selected ? _green : Colors.grey.shade400,
              ),
            ),
          ),
          _stepperBtn(
            icon: Icons.add,
            enabled: _canPlus,
            onTap: onIncrement,
          ),
        ]),
      ]),
    );
  }

  Widget _stepperBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? _green.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: enabled ? _green.withValues(alpha: 0.3) : Colors.grey.shade200),
        ),
        child: Icon(icon,
            size: 14, color: enabled ? _green : Colors.grey.shade400),
      ),
    );
  }
}
