import 'package:flutter/material.dart';

/// Бозор экранлари сарлавҳасидаги кичик ҚИЗИЛ «+» (Аралаш `cheap-add-ad` ва `MarketScreen` билан бир хил
/// кўриниш: 32×32 кўринади, босиш майдони 48×48). 7-босқич (эга, 2026-11-15): Уй-жой, Улгуржи, Хитой.
class MarketAddButton extends StatelessWidget {
  const MarketAddButton({super.key, required this.onTap, required this.tooltip});

  static const Color red = Color(0xFFF44336);

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: red, borderRadius: BorderRadius.circular(9)),
                child: Tooltip(
                  message: tooltip,
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
