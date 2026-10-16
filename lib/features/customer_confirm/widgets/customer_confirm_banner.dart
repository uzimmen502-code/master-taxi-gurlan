import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/customer_confirm.dart';
import '../../../services/customer_confirm_service.dart';
import '../customer_confirm_controller.dart';
import '../screens/customer_confirm_screen.dart';
import 'customer_confirm_card.dart';

/// Мижознинг бош саҳифасидаги «Тасдиқлаш кутилмоқда» блоки.
///
/// Рўйхат бўш бўлса ёки юклаб бўлмаса (эски сервер: функция йўқ; тармоқ йўқ)
/// БУТУНЛАЙ йўқолади — бош саҳифада хато кўрсатилмайди. Юклаш: очилганда,
/// иловага қайтганда (20 с дан кам бўлмаса), FCM `customer_confirm` келганда.
class CustomerConfirmBanner extends StatefulWidget {
  const CustomerConfirmBanner({
    super.key,
    this.service,
    this.maxInline = 2,
  });

  final CustomerConfirmService? service;

  /// Шундан ортиғи «Яна N та» орқали алоҳида экранда.
  final int maxInline;

  @override
  State<CustomerConfirmBanner> createState() => _CustomerConfirmBannerState();
}

class _CustomerConfirmBannerState extends State<CustomerConfirmBanner>
    with WidgetsBindingObserver {
  late final CustomerConfirmController _ctrl =
      CustomerConfirmController(service: widget.service);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CustomerConfirmSignal.tick.addListener(_onSignal);
    _ctrl.addListener(_onChanged);
    _ctrl.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CustomerConfirmSignal.tick.removeListener(_onSignal);
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onSignal() => _ctrl.load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ctrl.loadIfStale();
  }

  Future<void> _confirm(CustomerConfirmation item) async {
    final errKey = await _ctrl.confirm(item);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(context.tr(errKey ?? 'customer_confirm_done')),
      backgroundColor: errKey == null ? null : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openAll() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerConfirmScreen(service: widget.service),
      ),
    );
    if (mounted) _ctrl.load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _ctrl.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final c = context.ava;
    final shown = items.take(widget.maxInline).toList();
    final more = items.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.warnSoft,
          borderRadius: BorderRadius.circular(AvaRadius.card + 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: Text(
                context.tr('customer_confirm_title'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ),
            for (final item in shown) ...[
              CustomerConfirmCard(
                key: ValueKey(item.key),
                item: item,
                busy: _ctrl.isBusy(item),
                onConfirm: () => _confirm(item),
              ),
              const SizedBox(height: 8),
            ],
            if (more > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _openAll,
                  child: Text(
                    context
                        .tr('customer_confirm_more')
                        .replaceAll('{n}', '$more'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
