import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../local_taxi_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../services/local_taxi_payment_service.dart';
import '../../../../shared/widgets/wallet_topup_ui.dart';
import '../../../../utils/wallet_payment.dart';

/// Yo'lovchi — yo'lkirani hamyondan to'liq/qisman to'lash (intent).
class LocalTaxiWalletPanel extends StatefulWidget {
  const LocalTaxiWalletPanel({
    super.key,
    required this.tripId,
    required this.walletBalance,
    required this.fareEstimate,
    required this.initialIntent,
    required this.enabled,
  });

  final String tripId;
  final int walletBalance;
  final int fareEstimate;
  final int initialIntent;
  final bool enabled;

  @override
  State<LocalTaxiWalletPanel> createState() => _LocalTaxiWalletPanelState();
}

class _LocalTaxiWalletPanelState extends State<LocalTaxiWalletPanel> {
  late double _sliderValue;
  Timer? _debounce;
  bool _saving = false;
  bool _error = false;

  /// Yo'lovchi slayderni o'zi qo'zg'atganmi (aks holda saqlangan intent bilan sinxron).
  bool _touched = false;

  int get _maxWallet => WalletPayment.maxDebitFromWallet(
        widget.walletBalance,
        widget.fareEstimate > 0 ? widget.fareEstimate : widget.walletBalance,
      );

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.initialIntent.clamp(0, _maxWallet).toDouble();
  }

  @override
  void didUpdateWidget(covariant LocalTaxiWalletPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxW = _maxWallet;
    // Balans yoki saqlangan intent keyin kelsa — slayder saqlangan summani
    // ko'rsatsin (aks holda 0 ko'rinadi, server esa saqlangan summani yechadi).
    if (!_touched &&
        (widget.initialIntent != oldWidget.initialIntent ||
            widget.walletBalance != oldWidget.walletBalance)) {
      _sliderValue = widget.initialIntent.clamp(0, maxW).toDouble();
    }
    if (_sliderValue > maxW) {
      _sliderValue = maxW.toDouble();
      _scheduleSave(maxW);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleSave(int amount) {
    if (!widget.enabled || widget.tripId.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        _saving = true;
        _error = false;
      });
      try {
        await LocalTaxiPaymentService.setPassengerWalletIntent(
          tripId: widget.tripId,
          amount: amount,
        );
      } catch (e) {
        debugPrint('wallet intent: $e');
        if (mounted) setState(() => _error = true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    final maxW = _maxWallet;
    final fare = widget.fareEstimate;
    final cashDue = (fare - _sliderValue.round()).clamp(0, 999999999);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LocalTaxiColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LocalTaxiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('local_wallet_pay_title'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppText.bodyMedium,
                  ),
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.trMsg('local_wallet_balance_line', params: {
              'balance': formatPrice(widget.walletBalance),
              'fare': formatPrice(fare),
            }),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (maxW <= 0) ...[
            const SizedBox(height: 8),
            Text(
              context.tr('local_wallet_cash_only_hint'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              context.trMsg('local_wallet_split_line', params: {
                'wallet': formatPrice(_sliderValue.round()),
                'cash': formatPrice(cashDue),
              }),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            Slider(
              value: _sliderValue.clamp(0, maxW.toDouble()),
              min: 0,
              max: maxW.toDouble(),
              divisions: maxW > 0 ? maxW.clamp(1, 200) : 1,
              label: formatPrice(_sliderValue.round()),
              onChanged: (v) {
                setState(() {
                  _sliderValue = v;
                  _touched = true;
                });
                _scheduleSave(v.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sliderValue = 0;
                      _touched = true;
                    });
                    _scheduleSave(0);
                  },
                  child: Text(context.tr('local_wallet_cash_only')),
                ),
                TextButton(
                  onPressed: maxW > 0
                      ? () {
                          setState(() {
                            _sliderValue = maxW.toDouble();
                            _touched = true;
                          });
                          _scheduleSave(maxW);
                        }
                      : null,
                  child: Text(context.tr('local_wallet_full')),
                ),
              ],
            ),
          ],
          // Нақд тўлаш мумкин, шунинг учун мажбурий эмас — лекин ҳамён
          // етмаса тўлдиришнинг ўзи йўли бор (аввал ҳеч қаерда йўқ эди).
          if (fare > 0 && widget.walletBalance < fare)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('local-taxi-wallet-topup'),
                onPressed: () => openWalletTopUp(Navigator.of(context)),
                icon: const Icon(Icons.add_card_outlined, size: 18),
                label: Text(context.tr('wlt_topup_btn')),
              ),
            ),
          if (_error)
            Text(context.tr('local_wallet_save_failed'), style: TextStyle(color: LocalTaxiColors.danger, fontSize: 12)),
        ],
      ),
    );
  }
}
