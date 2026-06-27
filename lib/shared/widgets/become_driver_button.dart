import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';

/// AppBar'даги "Ҳайдовчи бўлиш" pill тугмаси.
///
/// Аввал local_taxi ва intercity йўловчи экранларида айнан такрорланарди
/// (фақат акцент ранги фарқли эди). Энди ягона виджет — [color] орқали
/// модулга мослаштирилади.
class BecomeDriverButton extends StatelessWidget {
  const BecomeDriverButton({
    super.key,
    required this.onTap,
    this.loading = false,
    this.color = AppColors.primaryMid,
  });

  final VoidCallback? onTap;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: loading ? 0.6 : 1,
        child: GestureDetector(
          onTap: loading ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(loading ? 'Юкланмоқда...' : context.tr('become_driver'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
