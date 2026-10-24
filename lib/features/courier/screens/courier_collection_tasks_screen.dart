import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/collection_task.dart';
import '../../../repositories/collection_tasks_repository.dart';
import '../../../shared/widgets/load_error_view.dart';
import 'courier_collection_detail_screen.dart';

/// Курьер — қабул (йиғиб олиш) вазифалари рўйхати.
class CourierCollectionTasksScreen extends StatefulWidget {
  const CourierCollectionTasksScreen({super.key, required this.courierUid});

  final String courierUid;

  @override
  State<CourierCollectionTasksScreen> createState() =>
      _CourierCollectionTasksScreenState();
}

class _CourierCollectionTasksScreenState
    extends State<CourierCollectionTasksScreen> {
  late Stream<List<CollectionTask>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _open();
  }

  Stream<List<CollectionTask>> _open() => context
      .read<CollectionTasksRepository>()
      .watchForCourier(widget.courierUid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('crr_task_list_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<List<CollectionTask>>(
        stream: _stream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return LoadErrorView(
              error: snap.error!,
              onRetry: () => setState(() => _stream = _open()),
            );
          }
          final tasks = snap.data ?? const <CollectionTask>[];
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📦', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('crr_task_list_empty'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: tasks.length,
            itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final CollectionTask task;

  /// Holat matni — model (`CollectionTask.statusLabel`) kirill literal
  /// qaytaradi, shuning uchun bu yerda l10n kalitiga o'giramiz.
  String _statusText(BuildContext context) {
    switch (task.status) {
      case 'collecting':
        return context.tr('crr_task_status_collecting');
      case 'completed':
        return context.tr('crr_task_status_completed');
      case 'cancelled':
        return context.tr('crr_task_status_cancelled');
      default:
        return context.tr('crr_task_status_assigned');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCollecting = task.status == 'collecting';
    final badgeColor = isCollecting ? Colors.blue : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CourierCollectionDetailScreen(task: task),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.customerName.isNotEmpty
                          ? task.customerName
                          : '+${task.customerPhone}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusText(context),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCollecting
                            ? Colors.blue.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              if (task.pickupAddress.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        task.pickupAddress,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    context.trMsg('crr_task_items_count',
                        params: {'n': '${task.items.length}'}),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.trMsg('crr_task_sum_line',
                        params: {'amount': formatMoney(task.totalValue)}),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
