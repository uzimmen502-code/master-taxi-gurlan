import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/ava_tokens.dart';
import '../../core/utils/user_error.dart';

/// Ro'yxat / ekran yuklanmaganda ko'rsatiladigan xato holati: tushunarli matn
/// (xom `snap.error` EMAS) va «Qayta urinish» tugmasi (≥ 48 dp).
///
/// ```dart
/// if (snap.hasError) {
///   return LoadErrorView(error: snap.error!, onRetry: () => setState(() {}));
/// }
/// ```
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({
    super.key,
    this.error,
    this.messageKey,
    this.onRetry,
  }) : assert(error != null || messageKey != null);

  /// Xato obyekti — matn [userErrorMessage] orqali tanlanadi (log'ga yoziladi).
  final Object? error;

  /// Aniq l10n kaliti (berilsa [error] dan ustun).
  final String? messageKey;

  /// `null` bo'lsa tugma ko'rsatilmaydi.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final message = messageKey != null
        ? context.tr(messageKey!)
        : userErrorMessage(context, error!, fallbackKey: 'err_load_failed');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.cloud_off_outlined, size: 44, color: c.ink2),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.35, color: c.ink2),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 48),
                ),
                child: Text(context.tr('err_retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
