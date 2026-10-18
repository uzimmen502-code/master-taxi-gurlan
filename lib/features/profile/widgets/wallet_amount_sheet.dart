import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// «Қанча тўлдирасиз?» — ботни очишдан ОЛДИН сумма танлаш (2026-10-18).
///
/// Нега: аввал фойдаланувчи ботда суммани қайта ёзарди. Энди илова етишмаётган
/// суммани таклиф қилади, лекин фойдаланувчи КЎПРОҚ (ёки бошқа) сумма ҳам
/// танлай олади. Танланган сумма ботга `start=deposit_<сумма>` билан кетади;
/// ҳал қилувчи лимит текшируви (бир сўров ва кунлик) ботда, серверда.

/// Тайёр суммалар. Бизнес қоида эмас — фақат қулайлик (лимитни сервер белгилайди).
const List<int> kWalletAmountPresets = [50000, 100000, 200000, 300000, 500000];

/// Тугмалар рўйхати: аввал таклиф (етишмаётган сумма, минг сўмгача юқорига
/// яхлитланади), кейин ундан КАТТА тайёр суммалар. [max] > 0 бўлса — ундан
/// каттаси чиқарилмайди.
List<int> walletAmountOptions({int? suggested, int max = 0}) {
  bool ok(int v) => v > 0 && (max <= 0 || v <= max);
  final out = <int>[];
  int? s;
  if (suggested != null && suggested > 0) {
    final rounded = ((suggested + 999) ~/ 1000) * 1000;
    // Таклиф лимитдан катта бўлса — чиқарилмайди ва тайёр суммалар филтрланмайди
    // (бир сўровга сиғадиган энг катта суммалар кўринсин).
    if (ok(rounded)) {
      s = rounded;
      out.add(rounded);
    }
  }
  for (final p in kWalletAmountPresets) {
    if (!ok(p) || out.contains(p)) continue;
    if (s != null && p < s) continue;
    out.add(p);
  }
  return out;
}

/// Сумма: бутун сон, 1..[max] (max <= 0 — юқори чегара номаълум). Акс ҳолда `null`.
int? parseWalletAmount(String raw, {int max = 0}) {
  final digits = raw.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{1,9}$').hasMatch(digits)) return null;
  final v = int.parse(digits);
  if (v <= 0) return null;
  if (max > 0 && v > max) return null;
  return v;
}

/// Бот ҳаволаси: `/start deposit_<сумма>` (бот уни `parseDepositPayload`да ўқийди;
/// формат иккала томонда бир хил бўлиши шарт).
String walletBotDepositUrl(String botUsername, int amount) =>
    'https://t.me/$botUsername?start=deposit_$amount';

/// Танланган суммани қайтаради (`null` — бекор қилинди).
Future<int?> showWalletAmountSheet(
  BuildContext context, {
  int? suggested,
  int max = 0,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => WalletAmountSheet(suggested: suggested, max: max),
  );
}

class WalletAmountSheet extends StatefulWidget {
  const WalletAmountSheet({super.key, this.suggested, this.max = 0});

  final int? suggested;
  final int max;

  @override
  State<WalletAmountSheet> createState() => _WalletAmountSheetState();
}

class _WalletAmountSheetState extends State<WalletAmountSheet> {
  final _custom = TextEditingController();
  int? _picked;

  late final List<int> _options =
      walletAmountOptions(suggested: widget.suggested, max: widget.max);

  @override
  void initState() {
    super.initState();
    // Таклиф бор бўлса — олдиндан танланган (бир босишда давом этилади).
    if (widget.suggested != null && _options.isNotEmpty) _picked = _options.first;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// Ҳозирги ҳақиқий танлов: ёзилган сумма устун, акс ҳолда тугма.
  int? get _value {
    if (_custom.text.trim().isNotEmpty) {
      return parseWalletAmount(_custom.text, max: widget.max);
    }
    return _picked;
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final customInvalid = _custom.text.trim().isNotEmpty &&
        parseWalletAmount(_custom.text, max: widget.max) == null;
    final value = _value;
    final suggestedLabel = _options.isNotEmpty && widget.suggested != null
        ? _options.first
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('wlt_amt_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in _options)
                  ChoiceChip(
                    key: ValueKey('wallet-amount-$v'),
                    label: Text(
                      v == suggestedLabel
                          ? context.trMsg('wlt_amt_suggested', params: {'amount': formatMoney(v)})
                          : formatMoney(v),
                    ),
                    selected: _custom.text.trim().isEmpty && _picked == v,
                    onSelected: (_) => setState(() {
                      _picked = v;
                      _custom.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('wallet-amount-custom'),
              controller: _custom,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
              decoration: InputDecoration(
                labelText: context.tr('wlt_amt_custom'),
                suffixText: context.tr('wlt_amt_currency'),
                errorText: customInvalid ? context.tr('wlt_amt_invalid') : null,
                helperText: widget.max > 0
                    ? context.trMsg('wlt_amt_max', params: {'max': formatMoney(widget.max)})
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('wallet-amount-continue'),
              onPressed: value == null ? null : () => Navigator.pop(context, value),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                value == null
                    ? context.tr('wlt_amt_continue')
                    : context.trMsg('wlt_amt_continue_amount', params: {'amount': formatMoney(value)}),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
