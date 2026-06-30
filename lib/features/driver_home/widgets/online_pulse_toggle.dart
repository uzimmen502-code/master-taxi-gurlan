import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Онлайн toggle — пульсация анимацияли.
class OnlinePulseToggle extends StatefulWidget {
  const OnlinePulseToggle({
    super.key,
    required this.isOnline,
    required this.onTap,
  });

  final bool isOnline;
  final VoidCallback onTap;

  @override
  State<OnlinePulseToggle> createState() => _OnlinePulseToggleState();
}

class _OnlinePulseToggleState extends State<OnlinePulseToggle>
    with SingleTickerProviderStateMixin {
  static const _green = AppColors.primaryDark;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.isOnline;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isOnline ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isOnline
                  ? _green.withValues(alpha: 0.4)
                  : Colors.grey.shade300,
              width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
          ],
        ),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: (isOnline ? _green : Colors.grey).withValues(alpha: 
                      isOnline ? _pulseAnim.value * 0.3 : 0.1),
                  shape: BoxShape.circle),
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: isOnline ? _green : Colors.grey,
                      shape: BoxShape.circle),
                  child: Icon(isOnline ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
                    style: TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color: isOnline ? _green : Colors.grey.shade600)),
                Text(
                    isOnline
                        ? 'Буюртмалар қабул қилинмоқда'
                        : 'Буюртмалар тўхтатилган',
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 28,
            decoration: BoxDecoration(
                color: isOnline ? _green : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment:
                  isOnline ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
