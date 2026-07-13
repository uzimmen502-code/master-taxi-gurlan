import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';

class OilHistoryScreen extends StatelessWidget {
  const OilHistoryScreen({
    super.key,
    required this.uid,
    required this.vehicle,
  });

  final String uid;
  final OilVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final repo = OilChangeRepository();
    final df = DateFormat('dd.MM.yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('oil_my_history_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<OilHistoryEntry>>(
        stream: repo.watchHistory(uid, vehicle.id),
        builder: (context, snap) {
          final items = snap.data ?? const <OilHistoryEntry>[];
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('oil_history_empty_hint'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = items[i];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  title: Text(
                    context.tr('oil_history_entry').replaceAll(
                          '{date}',
                          df.format(e.changedAt),
                        ).replaceAll(
                          '{km}',
                          formatPrice(e.odometerKm),
                        ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      if (e.oilType.isNotEmpty) e.oilType,
                      if (e.serviceName.isNotEmpty) e.serviceName,
                      if (e.note.isNotEmpty) e.note,
                    ].join(' · '),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
