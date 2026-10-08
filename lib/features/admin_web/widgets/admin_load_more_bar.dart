import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Admin рўйхати охиридаги «Яна юклаш» (эга, 2026-10-08): рўйхат аввал
/// 500 та билан очилади, тугма кейинги 500 тасини олиб келади.
class AdminLoadMoreBar extends StatelessWidget {
  const AdminLoadMoreBar({
    super.key,
    required this.loading,
    required this.failed,
    required this.onPressed,
  });

  final bool loading;

  /// Охирги уриниш муваффақиятсиз — тугма қолади, қайта босиш мумкин.
  final bool failed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (failed && !loading) ...[
            const Text(
              'Юклаб бўлмади. Қайта уриниб кўринг.',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 8),
          ],
          if (loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.expand_more),
              label: const Text('Яна юклаш'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
        ]),
      ),
    );
  }
}
