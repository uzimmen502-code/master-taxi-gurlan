import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/settings_repository.dart';

class OilServicesScreen extends StatelessWidget {
  const OilServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = OilChangeRepository();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('oil_services_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<OilServicePoint>>(
        stream: repo.watchServicePoints(),
        builder: (context, snap) {
          final points = snap.data ?? const <OilServicePoint>[];
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (points.isEmpty) {
            return FutureBuilder<String>(
              future: SettingsRepository().getDispatcherPhone(),
              builder: (context, phoneSnap) {
                final phone = phoneSnap.data ?? '';
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _pointCard(
                      context,
                      name: context.tr('oil_service_default_name'),
                      address: context.tr('oil_service_default_address_via'),
                      phone: phone,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('oil_services_empty_hint'),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                );
              },
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: points.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = points[i];
              return _pointCard(
                context,
                name: p.name,
                address: p.address,
                phone: p.phone,
              );
            },
          );
        },
      ),
    );
  }

  Widget _pointCard(
    BuildContext context, {
    required String name,
    required String address,
    required String phone,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(address),
            ],
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => callPhone(phone),
                icon: const Icon(Icons.phone),
                label: Text(phone),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
