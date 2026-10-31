import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// AVAGram лентаси бўш ёки юкланмаган ҳолат (қора фон).
///
/// [errorKey] берилса — хато матни ва «Қайта уриниш»; акс ҳолда «Ҳозирча
/// видеолар йўқ» ва «Видео жойлаш». Иккаласида ҳам ҳудуд тугмалари
/// ([filters]) ва «Орқага» бор: аввал бу ҳолатда ҳудудни алмаштириб ҳам,
/// экрандан чиқиб ҳам бўлмасди (ҳудуд тугмалари фақат клип ичида чизилади,
/// таб режимида AppBar'да орқага стрелка йўқ).
class TvFeedEmptyView extends StatelessWidget {
  const TvFeedEmptyView({
    super.key,
    required this.onPublish,
    required this.onRetry,
    required this.onBack,
    required this.filters,
    this.errorKey,
  });

  /// Хато матнининг l10n калити; `null` — лента шунчаки бўш.
  final String? errorKey;
  final VoidCallback onPublish;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    final isError = errorKey != null;
    final primaryStyle = FilledButton.styleFrom(
      backgroundColor: AvaLight.ok,
      foregroundColor: Colors.black,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    // Тана AppBar (табчалар, ~104 px) остидан бошланади — тепа бўшлиқ шу
    // учун; кичик экранда сиғмаса скролл бўлади.
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 112, 32, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isError ? Icons.cloud_off_outlined : Icons.videocam_outlined,
                  color: Colors.white70,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.tr(isError ? errorKey! : 'tv_market_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              if (isError)
                FilledButton.icon(
                  key: const ValueKey('tv_feed_retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(
                    context.tr('err_retry'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: primaryStyle,
                )
              else
                FilledButton.icon(
                  key: const ValueKey('tv_feed_publish'),
                  onPressed: onPublish,
                  icon: const Icon(Icons.videocam_rounded, size: 20),
                  label: Text(
                    context.tr('tv_publish_fab'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: primaryStyle,
                ),
              const SizedBox(height: 20),
              filters,
              const SizedBox(height: 16),
              TextButton.icon(
                key: const ValueKey('tv_feed_back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                label: Text(
                  context.tr('back'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
