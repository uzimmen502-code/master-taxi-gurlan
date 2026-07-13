import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/collection_task.dart';
import '../../../models/sell_submission.dart';
import '../../../repositories/collection_tasks_repository.dart';

/// Platforma taklifi kartasi — status, yig‘ish, summa, forward.
class SellSubmissionTile extends StatelessWidget {
  const SellSubmissionTile({
    super.key,
    required this.submission,
    this.showOwnerExtras = true,
  });

  final SellSubmission submission;
  final bool showOwnerExtras;

  Color get _statusColor {
    final s = submission;
    if (s.collectionCompleted) return Colors.green.shade800;
    if (s.inCollection) return Colors.blue.shade800;
    if (s.status == 'pending') return Colors.orange.shade800;
    if (s.status == 'archived') return Colors.grey.shade700;
    return Colors.green.shade800;
  }

  @override
  Widget build(BuildContext context) {
    final date = submission.createdAt;
    final when =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final summary = submission.items
        .map((e) => '${e.productName} · ${e.quantityText}')
        .join('; ');
    final total = submission.estimatedTotal;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  submission.progressLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: _statusColor,
                  ),
                ),
              ),
              if (submission.isForwarded) ...[
                const SizedBox(width: 6),
                Icon(Icons.campaign_outlined,
                    size: 16, color: Colors.teal.shade700),
                const SizedBox(width: 2),
                Text(
                  submission.forwardAudienceLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                when,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          if (total > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Таклиф: ${formatPrice(total)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
          if (showOwnerExtras &&
              submission.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Админ: ${submission.adminNote}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
          if (showOwnerExtras &&
              submission.collectionTaskId.isNotEmpty) ...[
            const SizedBox(height: 6),
            _CollectionProgressLine(taskId: submission.collectionTaskId),
          ],
        ],
      ),
    );
  }
}

class _CollectionProgressLine extends StatelessWidget {
  const _CollectionProgressLine({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: context.read<CollectionTasksRepository>().getById(taskId),
      builder: (context, snap) {
        final task = snap.data;
        if (task == null) {
          return Text(
            'Йиғиш вазифаси: $taskId',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          );
        }
        final value = task.finalValue > 0 ? task.finalValue : task.totalValue;
        return Row(
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${CollectionTask.statusLabel(task.status)}'
                '${value > 0 ? ' · ${formatPrice(value)}' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
