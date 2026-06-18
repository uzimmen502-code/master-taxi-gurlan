import 'package:flutter/material.dart';

import '../painters/calligraphic_border_painter.dart';

/// Hamyon kartasi — yashil fon + oltin kalligrafik ramka.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.balance,
    required this.lastTxAmount,
    required this.lastTxLabel,
    this.onHistoryTap,
  });

  final String balance;
  final String lastTxAmount;
  final String lastTxLabel;
  final VoidCallback? onHistoryTap;

  static const _green = Color(0xFF36A63A);
  static const _gold = Color(0xFFF5C518);
  static const _badgeText = Color(0xFF1A5E1C);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onHistoryTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: CalligraphicBorderPainter(isCompact: false),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Balans',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              balance,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Faol',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _badgeText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.receipt_outlined,
                            size: 15,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Oxirgi: $lastTxAmount',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                lastTxLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.54),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: _gold,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Tarix',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _gold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
