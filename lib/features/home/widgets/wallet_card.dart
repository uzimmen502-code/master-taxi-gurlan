import 'package:flutter/material.dart';

import '../painters/calligraphic_border_painter.dart';

/// Hamyon kartasi — yashil fon + oltin kalligrafik ramka.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.balance,
    required this.lastTxAmount,
    required this.displayName,
    this.lastTxIsCredit,
    this.onHistoryTap,
  });

  final String balance;
  final String lastTxAmount;
  final String displayName;

  /// `true` — kirim (oq), `false` — chiqim (qizil), `null` — tranzaksiya yo'q.
  final bool? lastTxIsCredit;
  final VoidCallback? onHistoryTap;

  static const _green = Color(0xFF36A63A);
  static const _gold = Color(0xFFF5C518);
  static const _badgeText = Color(0xFF1A5E1C);
  static const _debitTint = Color(0xFFFFCDD2);

  // Тўқ металлик 3D effekt учун градиент стопллари (юқоридан пастга:
  // ёруғ металл → асосий → тўқ соя — ёруғлик акси таассуроти).
  static const _metalLight = Color(0xFF9DA3A8);
  static const _metalBase = Color(0xFF6E7378);
  static const _metalDark = Color(0xFF3E4347);

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
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Balans',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
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
                      const SizedBox(height: 3),
                      Center(
                        child: Text(
                          balance,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
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
                            child: ShaderMask(
                              shaderCallback: (bounds) =>
                                  const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_metalLight, _metalBase, _metalDark],
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
                                      color: Color(0x99000000),
                                    ),
                                    Shadow(
                                      offset: Offset(0, -0.5),
                                      blurRadius: 0.5,
                                      color: Color(0x66FFFFFF),
                                    ),
                                  ],
                                ),
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
