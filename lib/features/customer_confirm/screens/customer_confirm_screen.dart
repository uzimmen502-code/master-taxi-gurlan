import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/customer_confirm.dart';
import '../../../services/customer_confirm_service.dart';
import '../customer_confirm_controller.dart';
import '../widgets/customer_confirm_card.dart';

/// «Тасдиқлаш кутилмоқда» — тўлиқ рўйхат. Очилиш йўллари: FCM
/// `customer_confirm` босилганда ва бош саҳифа блокидан («Яна N та»).
/// Очилганда юклайди, pull-to-refresh, тасдиқдан кейин рўйхат янгиланади.
class CustomerConfirmScreen extends StatefulWidget {
  const CustomerConfirmScreen({super.key, this.service});

  final CustomerConfirmService? service;

  @override
  State<CustomerConfirmScreen> createState() => _CustomerConfirmScreenState();
}

class _CustomerConfirmScreenState extends State<CustomerConfirmScreen> {
  late final CustomerConfirmController _ctrl =
      CustomerConfirmController(service: widget.service);

  @override
  void initState() {
    super.initState();
    CustomerConfirmSignal.tick.addListener(_onSignal);
    _ctrl.addListener(_onChanged);
    _ctrl.load();
  }

  @override
  void dispose() {
    CustomerConfirmSignal.tick.removeListener(_onSignal);
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onSignal() => _ctrl.load();

  Future<void> _confirm(CustomerConfirmation item) async {
    final errKey = await _ctrl.confirm(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(errKey ?? 'customer_confirm_done')),
      backgroundColor: errKey == null ? null : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _centered(Widget child) => LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _body(BuildContext context) {
    final items = _ctrl.items;
    if (!_ctrl.loaded && _ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Хато «бўш» деб яширилмайди; эски рўйхат бўлса — уни кўрсатамиз.
    if (!_ctrl.loaded && _ctrl.loadError != null) {
      return _centered(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('customer_confirm_err_load'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _ctrl.load,
            child: Text(context.tr('customer_confirm_refresh')),
          ),
        ],
      ));
    }
    if (items.isEmpty) {
      return _centered(Text(
        context.tr('customer_confirm_empty'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600),
      ));
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => CustomerConfirmCard(
        key: ValueKey(items[i].key),
        item: items[i],
        busy: _ctrl.isBusy(items[i]),
        onConfirm: () => _confirm(items[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('customer_confirm_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: RefreshIndicator(
        onRefresh: _ctrl.load,
        child: _body(context),
      ),
    );
  }
}
