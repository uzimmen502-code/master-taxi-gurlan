import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/wallet_ledger_labels.dart';

/// Ҳамён экранидаги матнлар учун таржима функцияси (`WalletTr`): параметрли
/// матнлар (`{module}`, `{amount}`) `trMsg` орқали.
WalletTr walletTr(BuildContext context) => (key, [params]) =>
    params == null ? context.tr(key) : context.trMsg(key, params: params);
