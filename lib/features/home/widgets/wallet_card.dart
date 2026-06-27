import 'package:flutter/material.dart';

import '../painters/calligraphic_border_painter.dart';

/// Hamyon kartasi — yashil fon + oltin kalligrafik ramka.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.balance,
    required this.lastTxAmount,
    required this.displayName,
    required this.dateText,
    required this.locationText,
    this.lastTxIsCredit,
    this.onHistoryTap,
  });

  final String balance;
  final String lastTxAmount;
  final String displayName;
  final String dateText;
  final String locationText;

  /// `true` — kirim (oq), `false` — chiqim (qizil), `null` — tranzaksiya yo'q.
  final bool? lastTxIsCredit;
  final VoidCallback? onHistoryTap;

  static const _green = Color(0xFF36A63A);
  static const _gold = Color(0xFFF5C518);
  static const _badgeText = Color(0xFF1A5E1C);
  static const _debitTint = Color(0xFFFFCDD2);

  static const _goldLight = Color(0xFFFFF4C2);
  static const _goldDark = Color(0xFFC9A000);

  Color get _txAmountColor {
    if (lastTxIsCredit == null) return Colors.white;
    return lastTxIsCredit! ? Colors.white : _debitTint;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.noScaling,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onHistoryTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              dateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              balance,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: ShaderMask(
                              shaderCallback: (bounds) =>
                                  const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_goldLight, _gold, _goldDark],
                                stops: [0.0, 0.5, 1.0],
                              ).createShader(bounds),
                              child: Text(
                                displayName.toUpperCase(),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 1,
                                      color: Color(0x66000000),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                                children: [
                                  const TextSpan(text: 'Oxirgi: '),
                                  TextSpan(
                                    text: lastTxAmount,
                                    style: TextStyle(color: _txAmountColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFAC775),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      locationText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
      ),
    );
  }
}
