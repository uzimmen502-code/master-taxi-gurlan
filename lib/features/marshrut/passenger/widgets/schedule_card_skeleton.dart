import 'package:flutter/material.dart';

/// ScheduleCard layoutiga mos skeleton (Phase B).
class ScheduleCardSkeletonList extends StatelessWidget {
  const ScheduleCardSkeletonList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(count, (_) => const ScheduleCardSkeleton()),
    );
  }
}

class ScheduleCardSkeleton extends StatefulWidget {
  const ScheduleCardSkeleton({super.key});

  @override
  State<ScheduleCardSkeleton> createState() => _ScheduleCardSkeletonState();
}

class _ScheduleCardSkeletonState extends State<ScheduleCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = 0.35 + _pulse.value * 0.25;
        return Opacity(opacity: t.clamp(0.35, 0.6), child: child);
      },
      child: Container(
        height: 132,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                _box(52, 52, radius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(double.infinity, 14),
                      const SizedBox(height: 8),
                      _box(160, 11),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _box(88, 22, radius: 8),
                          const SizedBox(width: 8),
                          _box(64, 22, radius: 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _box(double.infinity, 40, radius: 10),
          ],
        ),
      ),
    );
  }

  Widget _box(double width, double height, {double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
