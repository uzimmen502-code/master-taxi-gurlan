// АДМИН «Етказилмади — қарор» (эга қарорлари 2026-10-31): курьер «етказиб/олиб бўлмади» деди,
// мижоз `failedTimeoutMin` (стандарт 15) ичида жавоб бермади — гилам, сут, йиғишда админ,
// нон/бозорда сотувчи (захира — админ) ҳал қилади.
//   `listDeliveryFailedPending` (ўқиш) ва `resolveDeliveryFailed` (қарор, `admin_audit`) —
//   default codebase, us-central1. Ҳамма текширув ва ҳолат СЕРВЕРДА.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/delivery_failed_service.dart';
import '../../customer_confirm/widgets/delivery_failed_decision_list.dart';

class DeliveryFailedAdminScreen extends StatelessWidget {
  const DeliveryFailedAdminScreen({super.key, this.service});

  final DeliveryFailedService? service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text('Етказилмади — қарор', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [DeliveryFailedDecisionList(service: service)],
      ),
    );
  }
}
