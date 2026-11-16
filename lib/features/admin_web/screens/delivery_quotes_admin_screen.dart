import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../business_orders/data/business_orders_repository.dart';
import '../../business_orders/widgets/delivery_quote_requests_section.dart';

/// Админ: «Етказиш нархи сўровлари» («Бозорлар» STAGE 11) — йирик техника учун очиқ сўровлар ва нарх юбориш.
/// Сервер: `listOpenDeliveryQuotes` / `respondDeliveryQuote` (admin/superadmin, жавоб `admin_audit`га ёзилади).
/// Курьер панелидаги бўлим билан бир хил виджет ([DeliveryQuoteRequestsSection]).
class DeliveryQuotesAdminScreen extends StatefulWidget {
  const DeliveryQuotesAdminScreen({super.key, this.repository});

  final BusinessOrdersRepository? repository;

  @override
  State<DeliveryQuotesAdminScreen> createState() => _DeliveryQuotesAdminScreenState();
}

class _DeliveryQuotesAdminScreenState extends State<DeliveryQuotesAdminScreen> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('dq_requests_title')),
        actions: [
          IconButton(
            tooltip: context.tr('restaurants_courier_refresh'),
            onPressed: () => setState(() => _tick++),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
        children: [
          DeliveryQuoteRequestsSection(repository: _repo, refreshTick: _tick, showErrors: true),
        ],
      ),
    );
  }
}
