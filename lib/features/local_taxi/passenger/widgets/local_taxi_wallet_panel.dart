import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../services/local_taxi_payment_service.dart';
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
  String? _error;

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
        _error = null;
      });
      try {
        await LocalTaxiPaymentService.setPassengerWalletIntent(
          tripId: widget.tripId,
          amount: amount,
        );
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.blue.shade800, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Hamyon bilan to\'lash',
                  style: TextStyle(
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
            'Balans: ${formatPrice(widget.walletBalance)} · '
            'taxminiy yo\'lkira: ${formatPrice(fare)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (maxW <= 0) ...[
            const SizedBox(height: 8),
            Text(
              'Hamyon bo\'sh yoki yo\'lkira aniqlanmagan — faqat naqd.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Hamyon: ${formatPrice(_sliderValue.round())} · '
              'Naqd: ${formatPrice(cashDue)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
              ),
            ),
            Slider(
              value: _sliderValue.clamp(0, maxW.toDouble()),
              min: 0,
              max: maxW.toDouble(),
              divisions: maxW > 0 ? maxW.clamp(1, 200) : 1,
              label: formatPrice(_sliderValue.round()),
              onChanged: (v) {
                setState(() => _sliderValue = v);
                _scheduleSave(v.round());
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => _sliderValue = 0);
                    _scheduleSave(0);
                  },
                  child: const Text('Faqat naqd'),
                ),
                TextButton(
                  onPressed: maxW > 0
                      ? () {
                          setState(() => _sliderValue = maxW.toDouble());
                          _scheduleSave(maxW);
                        }
                      : null,
                  child: const Text('To\'liq hamyon'),
                ),
              ],
            ),
          ],
          if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
        ],
      ),
    );
  }
}
