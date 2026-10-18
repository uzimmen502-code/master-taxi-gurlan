import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/realty_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../profile/screens/wallet_screen.dart';
import 'realty_feedback.dart';

/// Кўчмас мулк: ҳамён билан боғлиқ ЯГОНА жой — баланс, «тўлдириш» тугмаси ва
/// баланс етмаганда хато.
///
/// Аввал баланс етмаса фақат «Ҳамённи тўлдиринг» матни чиқарди: тугма йўқ,
/// ҳамён эса пастки менюдан олиб ташланган — эга тўлдиришга йўл топа
/// олмасди (2026-10-18). Энди ҳар жойда ҳамён экрани (`WalletScreen`:
/// баланс + Telegram бот орқали тўлдириш) бир босишда очилади.

/// Эганинг баланси оқими. Телефон/Firebase йўқ бўлса — бўш оқим
/// (баланс «номаълум»: ёлғон огоҳлантириш кўрсатилмайди).
Stream<int> realtyBalanceStream() {
  try {
    final uid = canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    if (uid.isEmpty) return const Stream<int>.empty();
    return UserRepository().watchBonusBalance(uid);
  } catch (_) {
    return const Stream<int>.empty();
  }
}

/// Ҳамён экранини очади (`WalletScreen` — баланс ва Telegram орқали тўлдириш).
Future<void> openRealtyWallet(NavigatorState navigator) {
  final phone = canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  return navigator.push(
    MaterialPageRoute<void>(builder: (_) => WalletScreen(phone: phone)),
  );
}

/// Харид хатоси. Баланс етмаса («insufficient_balance») хабарда
/// «Ҳамённи тўлдириш» ТУГМАСИ бўлади.
///
/// [messenger] ва [navigator] `await` дан ОЛДИН олиб қўйилади (контекст
/// ишончсиз). [openWallet] — тест учун алмаштириладиган ҳаракат.
void showRealtyPurchaseError({
  required BuildContext context,
  required ScaffoldMessengerState messenger,
  required NavigatorState navigator,
  required RealtyException error,
  VoidCallback? openWallet,
}) {
  final text = realtyErrorText(context, error);
  if (error.code != 'insufficient_balance') {
    showRealtyError(messenger, text);
    return;
  }
  showRealtyError(
    messenger,
    text,
    actionLabel: context.tr('realty_wallet_topup'),
    onAction: openWallet ?? () => openRealtyWallet(navigator),
  );
}

/// Варақ (modal bottom sheet) ИЧИДАГИ харид хатоси.
///
/// Нега snackbar эмас: варақ очиқ турганда snackbar унинг ОРТИДА қолади
/// (ҳам кўринмайди, ҳам босилмайди), шунинг учун хато ва «Ҳамённи тўлдириш»
/// тугмаси варақнинг ўзида кўрсатилади. [onTopUp] берилса — тугма чиқади.
class RealtyInlineError extends StatelessWidget {
  const RealtyInlineError({super.key, required this.text, this.onTopUp});

  final String text;
  final VoidCallback? onTopUp;

  /// Хато баланс етмаслигиданми (тугма чиқарилиши керакми).
  static bool needsTopUp(RealtyException e) => e.code == 'insufficient_balance';

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('realty-inline-error'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.dangerSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppText.labelTiny, color: c.danger, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTopUp != null)
            TextButton(
              key: const ValueKey('realty-inline-error-topup'),
              onPressed: onTopUp,
              child: Text(context.tr('realty_wallet_topup')),
            ),
        ],
      ),
    );
  }
}

/// Харид варағидаги баланс қатори:
///  * баланс етарли (ёки ҳали номаълум) — кичик «Ҳамёнда: X» ёзуви;
///  * етмаса ([price] > баланс) — огоҳлантириш: қанча етишмаслиги ва
///    «Ҳамённи тўлдириш» тугмаси.
/// Сотиб олиш тугмаси ЎЧИРИЛМАЙДИ: баланс эскирган бўлиши мумкин, ҳал
/// қилувчи — сервер.
class RealtyBalanceNotice extends StatelessWidget {
  const RealtyBalanceNotice({
    super.key,
    required this.balance,
    required this.price,
    required this.onTopUp,
  });

  final Stream<int> balance;

  /// Танланган харид нархи (`null` — ҳали танланмаган/юкланмаган).
  final int? price;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: balance,
      builder: (context, snap) => RealtyBalanceBar(
        balance: snap.data,
        price: price,
        onTopUp: onTopUp,
      ),
    );
  }
}

/// [RealtyBalanceNotice]нинг оқимсиз кўриниши: [balance] `null` — номаълум
/// (ҳеч нарса кўрсатилмайди, ёлғон огоҳлантириш йўқ).
class RealtyBalanceBar extends StatelessWidget {
  const RealtyBalanceBar({
    super.key,
    required this.balance,
    required this.price,
    required this.onTopUp,
  });

  final int? balance;
  final int? price;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final bal = balance;
    if (bal == null) return const SizedBox.shrink();
    final short = price != null && bal < price!;
    if (!short) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          context.trMsg('realty_wallet_balance', params: {'amount': formatMoney(bal)}),
          key: const ValueKey('realty-balance-info'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
        ),
      );
    }
    return Container(
      key: const ValueKey('realty-balance-short'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 18, color: c.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.trMsg(
                'realty_wallet_short',
                params: {'amount': formatMoney(price! - bal)},
              ),
              style: TextStyle(fontSize: AppText.labelTiny, color: c.warn, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const ValueKey('realty-balance-topup'),
            onPressed: onTopUp,
            child: Text(context.tr('realty_wallet_topup')),
          ),
        ],
      ),
    );
  }
}
