import 'dart:math' show max, min;

/// Барча кошелёк тўловлари учун умумий мантиқ: **аниқ сумма** (сут, гуруч, нон, овқат …).
///
/// - [maxDebitFromWallet] — `min(баланс, буюртма жами)`.
/// - [effectiveWalletApplied] — нақд + слайдер билан кошелёкдан қанча ечилиши.
/// - [coversOrder] — қарз қолмаслигини текширади.
///
/// Сервер: `placeOrderWithWallet`, `creditSupplier`, `creditChange` ҳам шу принципда
/// (1000 га мажбурий тўғрилаш йўқ).
class WalletPayment {
  WalletPayment._();

  /// Буюртмани тўлиқ қоплаш учун кошелёкдан ечилиши мумкин бўлган максимум: `min(balance, orderTotal)`.
  static int maxDebitFromWallet(int walletBalance, int orderTotal) {
    if (orderTotal <= 0 || walletBalance <= 0) return 0;
    return min(walletBalance, orderTotal);
  }

  /// Нақддан кейин кошелёкдан қопланishi керак бўлган минимум (сўм бўйича, аниқ).
  static int minWalletForCashCover(int orderTotal, int cashPaid) {
    if (orderTotal <= 0) return 0;
    if (cashPaid >= orderTotal) return 0;
    return orderTotal - cashPaid;
  }

  /// Слайдер + нақд: кошелёкдан реал ишлатиладиган сумма.
  ///
  /// - [cashPaid] ≥ [orderTotal] бўлса кошелёк **0** (барча нақдда).
  /// - Акс ҳолда: `max(слайдер, orderTotal - cashPaid)`, `maxDebitFromWallet` гача.
  static int effectiveWalletApplied({
    required int walletBalance,
    required int orderTotal,
    required int useBalanceSlider,
    required int cashPaid,
  }) {
    final maxW = maxDebitFromWallet(walletBalance, orderTotal);
    if (maxW <= 0 || orderTotal <= 0) return 0;
    if (cashPaid >= orderTotal) return 0;

    final slider = useBalanceSlider.clamp(0, maxW);
    final minNeed = minWalletForCashCover(orderTotal, cashPaid);
    return min(maxW, max(slider, minNeed));
  }

  /// `нақд + кошелёк` буюртмани тўлиқ қоплай оладими.
  static bool coversOrder({
    required int walletBalance,
    required int orderTotal,
    required int useBalanceSlider,
    required int cashPaid,
  }) {
    if (orderTotal <= 0) return true;
    final w = effectiveWalletApplied(
      walletBalance: walletBalance,
      orderTotal: orderTotal,
      useBalanceSlider: useBalanceSlider,
      cashPaid: cashPaid,
    );
    return cashPaid + w >= orderTotal;
  }

  /// Кошелёк **тўлиқ** `maxDebitFromWallet` билан ишлатилganda: `нақд + кошелёк ≥ жами`.
  static bool orderPayableWithAutoWallet({
    required int walletBalance,
    required int orderTotal,
    required int cashPaid,
  }) {
    if (orderTotal <= 0) return true;
    final w = maxDebitFromWallet(walletBalance, orderTotal);
    return cashPaid + w >= orderTotal;
  }
}
