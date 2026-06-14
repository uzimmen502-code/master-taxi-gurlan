import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../controllers/intercity_driver_panel_controller.dart';

/// Брон хабарлари архиви — сақлаш/ўчириш (archived flag).
class IntercityDriverMessagesScreen extends StatefulWidget {
  const IntercityDriverMessagesScreen({super.key, required this.driverId});

  final String driverId;

  @override
  State<IntercityDriverMessagesScreen> createState() =>
      _IntercityDriverMessagesScreenState();
}

class _IntercityDriverMessagesScreenState
    extends State<IntercityDriverMessagesScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => IntercityDriverPanelController(
        driverId: widget.driverId,
        driverName: '',
        driverPhone: '',
        driverCar: '',
        driverPlate: '',
        bookingsRepo: ctx.read<IntercityBookingsRepository>(),
        schedulesRepo: ctx.read<SchedulesRepository>(),
      )..init(includeArchived: true),
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('messages_title')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Consumer<IntercityDriverPanelController>(
          builder: (context, c, _) {
            final list = _showArchived
                ? c.bookings.where((b) => b.archivedByDriver).toList()
                : c.bookings.where((b) => !b.archivedByDriver).toList();
            if (list.isEmpty) {
              return Center(
                child: Text(_showArchived
                    ? context.tr('archive_empty')
                    : context.tr('no_messages')),
              );
            }
            return Column(
              children: [
                SwitchListTile(
                  title: Text(context.tr('show_archive')),
                  value: _showArchived,
                  onChanged: (v) => setState(() => _showArchived = v),
                ),
                Expanded(
                  child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final b = list[i];
                return Card(
                  child: ListTile(
                    title: Text(b.userName),
                    subtitle: Text(
                        '${b.routeDisplayLabel(Localizations.localeOf(context))}\n${formatPrice(b.totalAmount)} ${context.tr('sum')} · ${b.status}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'archive') {
                          await c.archive(b.id, archived: true);
                        } else if (v == 'restore') {
                          await c.archive(b.id, archived: false);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!b.archivedByDriver)
                          PopupMenuItem(
                              value: 'archive',
                              child: Text(context.tr('archive_save'))),
                        if (b.archivedByDriver)
                          PopupMenuItem(
                              value: 'restore',
                              child: Text(context.tr('archive_restore'))),
                      ],
                    ),
                  ),
                );
              },
            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
