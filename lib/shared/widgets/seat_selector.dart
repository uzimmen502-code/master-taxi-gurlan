import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 1..maxSeats оралиқдаги рақамларни танлаш widget'и. Driver flow'ларидa
/// (register, schedule) қайта ишлатилади.
class SeatSelector extends StatelessWidget {
  const SeatSelector({
    super.key,
    required this.value,
    required this.maxSeats,
    required this.onChanged,
    this.color = AppColors.primaryDark,
  });

  final int value;
  final int maxSeats;
  final ValueChanged<int> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(maxSeats, (i) => i + 1).map((n) {
        final sel = value == n;
        return GestureDetector(
          onTap: () => onChanged(n),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: sel ? color : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? color : Colors.grey.shade300),
            ),
            child: Center(
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: sel ? Colors.white : Colors.grey.shade600))),
          ),
        );
      }).toList(),
    );
  }
}
