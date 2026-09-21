import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_report.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../services/admin_ev_charging_service.dart';
import '../services/admin_auth_service.dart';

/// ⚡ EV zaryadlash nuqtalari moderatsiyasi (6-band) — `reportCount > 0`
/// stansiyalar navbati, har biri uchun report tafsilotlari, harakatlar.
class EvStationModerationScreen extends StatelessWidget {
  const EvStationModerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<EvStationRepository>();
    return StreamBuilder<List<EvChargingStation>>(
      stream: repo.watchReportedStations(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final stations = snap.data!;
        if (stations.isEmpty) {
          return const Center(child: Text('Report qilingan stansiyalar yo\'q.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: stations.length,
          itemBuilder: (context, i) => _StationModerationTile(station: stations[i]),
        );
      },
    );
  }
}

class _StationModerationTile extends StatefulWidget {
  const _StationModerationTile({required this.station});

  final EvChargingStation station;

  @override
  State<_StationModerationTile> createState() => _StationModerationTileState();
}

class _StationModerationTileState extends State<_StationModerationTile> {
  bool _busy = false;

  String get _adminPhone => context.read<AdminAuthService>().phoneDigits ?? '';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Хатолик: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final svc = context.read<AdminEvChargingService>();
    final repo = context.read<EvStationRepository>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(
          '⚡ ${station.latitude.toStringAsFixed(5)}, ${station.longitude.toStringAsFixed(5)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Report: ${station.reportCount} · Holat: ${station.status} · '
          '${station.isActive ? "aktiv" : "yashirilgan"}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<String>(
                  value: station.status,
                  items: const [
                    DropdownMenuItem(value: 'unknown', child: Text('unknown')),
                    DropdownMenuItem(value: 'working', child: Text('working')),
                    DropdownMenuItem(
                        value: 'partially_working', child: Text('partially_working')),
                    DropdownMenuItem(value: 'not_working', child: Text('not_working')),
                  ],
                  onChanged: _busy
                      ? null
                      : (status) {
                          if (status == null) return;
                          _run(() => svc.updateStationStatus(
                                adminPhone: _adminPhone,
                                stationId: station.id,
                                status: status,
                              ));
                        },
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => svc.setStationActive(
                            adminPhone: _adminPhone,
                            stationId: station.id,
                            isActive: !station.isActive,
                          )),
                  child: Text(station.isActive
                      ? 'Xaritadan yashirish'
                      : 'Xaritaga qaytarish'),
                ),
              ],
            ),
          ),
          StreamBuilder<List<EvChargingReport>>(
            stream: repo.watchReports(station.id),
            builder: (context, snap) {
              final reports = snap.data ?? const <EvChargingReport>[];
              if (reports.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Yuklanmoqda...'),
                );
              }
              return Column(
                children: reports
                    .map((r) => _ReportRow(
                          report: r,
                          busy: _busy,
                          onResolve: () => _run(() => svc.resolveReport(
                                adminPhone: _adminPhone,
                                stationId: station.id,
                                reportId: r.id,
                              )),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.report,
    required this.busy,
    required this.onResolve,
  });

  final EvChargingReport report;
  final bool busy;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(report.reason.label),
      subtitle: report.comment.isEmpty ? null : Text(report.comment),
      trailing: report.resolved
          ? const Icon(Icons.check_circle, color: AppColors.primaryDark)
          : TextButton(
              onPressed: busy ? null : onResolve,
              child: const Text('Ko\'rib chiqildi'),
            ),
    );
  }
}
