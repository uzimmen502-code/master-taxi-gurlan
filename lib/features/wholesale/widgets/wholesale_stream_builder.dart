import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Улгуржи экранларидаги `StreamBuilder` учун ягона қоида: хато бўлса
/// «бўш» ёки «рўйхатдан ўтиш» ҳолати ЭМАС, балки хато ва «Қайта уриниш».
///
/// Аввал `snap.hasError` текширилмас эди: лентада хато «маҳсулот йўқ»,
/// сотувчи ҳужжатида эса `null` → рўйхатдан ўтиш формаси бўлиб кўринарди
/// (тасдиқланган сотувчи ўзини қайта рўйхатдан ўтказишга мажбур бўларди).
///
/// [builder] га маълумот берилади; `T` `null` бўлиши мумкин (ҳужжат йўқ) —
/// бу хато эмас.
class WholesaleStreamBuilder<T> extends StatelessWidget {
  const WholesaleStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    required this.onRetry,
  });

  final Stream<T>? stream;
  final Widget Function(BuildContext context, T? data) builder;

  /// «Қайта уриниш» босилганда: чақирувчи янги stream ясаб, қайта чизади
  /// (Firestore stream хатодан кейин ёпилади, шунинг учун қайта уланиш керак).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[Wholesale] stream error: ${snap.error}');
          return WholesaleLoadError(onRetry: onRetry);
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return builder(context, snap.data);
      },
    );
  }
}

/// Юклаб бўлмади ҳолати: матн + 48 dp баландликдаги «Қайта уриниш».
/// Ички хато матни (exception) кўрсатилмайди.
class WholesaleLoadError extends StatelessWidget {
  const WholesaleLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(
              context.tr('wholesale_load_error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(context.tr('wholesale_retry')),
            ),
          ],
        ),
      ),
    );
  }
}
