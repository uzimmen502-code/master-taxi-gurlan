import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../features/profile/screens/wallet_screen.dart';
import '../../repositories/user_repository.dart';

/// ҲАМЁН ТЎЛДИРИШГА ЯГОНА ЙЎЛ: баланс етмаса фойдаланувчи ҳамён экранига
/// (`WalletScreen`: баланс + Telegram орқали тўлдириш) БИР босишда ўтади.
///
/// Аввал факат кўчмас мулк, ресторан, EV ва AI'да тугма бор эди; бошқа
/// модуллар «ҳамённи тўлдиринг» деб ёзарди, лекин босадиган жой бермасди,
/// ҳамён эса пастки менюдан яширин — эга тўлдиришга йўл топа олмасди
/// (2026-10-18). Энди ҳамма модул шу қатламдан фойдаланади (7-қоида).

/// Эганинг баланси оқими. Телефон/Firebase йўқ бўлса — бўш оқим (баланс
/// «номаълум»: ёлғон огоҳлантириш кўрсатилмайди).
///
/// ⚠️ Оқим КЎП МАРТА тингланиши мумкин (broadcast): `StreamBuilder` элементи
/// қайта яратилса ўша оқимни яна тинглайди. Одатдаги `async*` оқим бир марта
/// тингланади ва иккинчисида «Stream has already been listened to» берарди —
/// Кабинет қурилмада йиқилди (2026-10-18). Тингловчи қолмаса манба ёпилади,
/// янгиси келса қайта очилади.
Stream<int> walletBalanceStream() {
  StreamSubscription<int>? sub;
  late final StreamController<int> controller;
  controller = StreamController<int>.broadcast(
    onListen: () {
      sub = _walletBalanceSource().listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          // Телефон йўқ — манба тугади; тингловчилар «маълумот йўқ» деб қолади.
          if (!controller.isClosed) controller.close();
        },
      );
    },
    onCancel: () {
      sub?.cancel();
      sub = null;
    },
  );
  return controller.stream;
}

Stream<int> _walletBalanceSource() async* {
  final uid = await walletPhoneId();
  if (uid.isEmpty) return;
  yield* UserRepository().watchBonusBalance(uid);
}

/// Эганинг ҳамён ID'си (`users/{uid}`): аввал Firebase'даги телефон, бўлмаса
/// илованинг ўз сақланган телефони (`user_phone`, `ProfileController` ва
/// `HomeController` шундан ўқийди).
///
/// Нега: совуқ ишга туширилганда `FirebaseAuth.currentUser.phoneNumber` бир
/// муддат бўш бўлиши мумкин; аввал баланс оқими шунда бўш бўлиб қолар ва
/// Кабинетдаги «Ҳамён» қаторида баланс чиқмас эди (қурилмада кўрилди,
/// 2026-10-18). Телефон йўқ — бўш қатор (ёлғон «0» эмас).
Future<String> walletPhoneId() async {
  try {
    final auth = canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    if (auth.isNotEmpty) return auth;
  } catch (_) {
    // Firebase тайёр эмас — сақланган телефонга ўтамиз.
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    return canonicalPhoneId(prefs.getString('user_phone') ?? '');
  } catch (_) {
    return '';
  }
}

/// Ҳамён экранини очади. Қайтгач баланс оқими ўзи янгиланади.
///
/// [suggestedAmount] — етишмаётган сумма: «қанча тўлдирасиз» қадамида биринчи
/// таклиф бўлиб чиқади (фойдаланувчи ўзгартира олади).
Future<void> openWalletTopUp(NavigatorState navigator, {int? suggestedAmount}) async {
  final phone = await walletPhoneId();
  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => WalletScreen(phone: phone, suggestedAmount: suggestedAmount),
    ),
  );
}

/// Варақ (modal bottom sheet) ИЧИДАГИ хато.
///
/// Нега snackbar эмас: варақ очиқ турганда snackbar унинг ОРТИДА қолади (ҳам
/// кўринмайди, ҳам босилмайди). [onTopUp] берилса — «Ҳамённи тўлдириш» тугмаси.
class WalletInlineError extends StatelessWidget {
  const WalletInlineError({super.key, required this.text, this.onTopUp});

  final String text;
  final VoidCallback? onTopUp;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('wallet-inline-error'),
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
              key: const ValueKey('wallet-inline-error-topup'),
              onPressed: onTopUp,
              child: Text(context.tr('wlt_topup_btn')),
            ),
        ],
      ),
    );
  }
}

/// Харид варағидаги баланс қатори (оқим билан): етарли ёки номаълум —
/// кичик «Ҳамёнда: X»; етмаса ([price] > баланс) — қанча етишмаслиги ва
/// «Ҳамённи тўлдириш» тугмаси. Сотиб олиш тугмаси ЎЧИРИЛМАЙДИ: баланс
/// эскирган бўлиши мумкин, ҳал қилувчи — сервер.
class WalletBalanceNotice extends StatelessWidget {
  const WalletBalanceNotice({
    super.key,
    required this.balance,
    required this.price,
    required this.onTopUp,
    this.onTopUpAmount,
  });

  final Stream<int> balance;

  /// Танланган харид нархи (`null` — ҳали танланмаган/юкланмаган).
  final int? price;
  final VoidCallback onTopUp;

  /// Берилса — тугма босилганда [onTopUp] ўрнига етишмаётган сумма билан чақирилади.
  final ValueChanged<int>? onTopUpAmount;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: balance,
      builder: (context, snap) => WalletBalanceBar(
        balance: snap.data,
        price: price,
        onTopUp: onTopUp,
        onTopUpAmount: onTopUpAmount,
      ),
    );
  }
}

/// [WalletBalanceNotice]нинг оқимсиз кўриниши: [balance] `null` — номаълум
/// (ҳеч нарса кўрсатилмайди, ёлғон огоҳлантириш йўқ).
class WalletBalanceBar extends StatelessWidget {
  const WalletBalanceBar({
    super.key,
    required this.balance,
    required this.price,
    required this.onTopUp,
    this.onTopUpAmount,
  });

  final int? balance;
  final int? price;
  final VoidCallback onTopUp;
  final ValueChanged<int>? onTopUpAmount;

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
          context.trMsg('wlt_balance_info', params: {'amount': formatMoney(bal)}),
          key: const ValueKey('wallet-balance-info'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
        ),
      );
    }
    return Container(
      key: const ValueKey('wallet-balance-short'),
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
              context.trMsg('wlt_balance_short', params: {'amount': formatMoney(price! - bal)}),
              style: TextStyle(fontSize: AppText.labelTiny, color: c.warn, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const ValueKey('wallet-balance-topup'),
            onPressed: onTopUpAmount == null ? onTopUp : () => onTopUpAmount!(price! - bal),
            child: Text(context.tr('wlt_topup_btn')),
          ),
        ],
      ),
    );
  }
}
