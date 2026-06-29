import 'package:flutter/material.dart';

import '../../../models/queue_entry.dart';
import '../../../core/theme/app_theme.dart';

/// РќР°РІР±Р°С‚ СЂСћР№С…Р°С‚Рё вЂ” РїРѕР·РёС†РёСЏ + РєРµР№РёРЅРіРё РјР°СЂС€СЂСѓС‚.
class QueueCard extends StatelessWidget {
  const QueueCard({
    super.key,
    required this.queueList,
    required this.myPosition,
    required this.myDriverId,
  });

  final List<QueueEntry> queueList;
  final int myPosition;
  final String myDriverId;

  static const _blue = AppColors.primary;
  static const _green = AppColors.primaryDark;
  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    String nextRoute = '';
    if (queueList.isNotEmpty) {
      final first = queueList.first;
      if (first.to.isNotEmpty) {
        nextRoute = '${first.to} в†’ ${first.from}';
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.06),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.queue, color: _blue, size: 18),
            const SizedBox(width: 8),
            const Text('рџ“‹ РќР°РІР±Р°С‚ С‚РёР·РёРјРё',
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            if (myPosition > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: myPosition == 1 ? _green : _blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  myPosition == 1
                      ? 'рџҐ‡ РЎРёР· Р±РёСЂРёРЅС‡РёСЃРёР·!'
                      : '$myPosition-РЅР°РІР±Р°С‚',
                  style: const TextStyle(
                      fontSize: AppText.labelSmall,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ]),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: queueList.length,
          itemBuilder: (_, i) {
            final q = queueList[i];
            final isMe = q.driverId == myDriverId;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? _green.withValues(alpha: 0.06) : Colors.transparent,
                border: i < queueList.length - 1
                    ? Border(
                        bottom: BorderSide(color: Colors.grey.shade100))
                    : null,
              ),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? _green
                        : isMe
                            ? _blue
                            : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: AppText.labelSmall,
                              fontWeight: FontWeight.bold,
                              color: (i == 0 || isMe)
                                  ? Colors.white
                                  : Colors.grey.shade600))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? '${q.driverName} (РЎРёР·)' : q.driverName,
                          style: TextStyle(
                              fontSize: AppText.bodyMedium,
                              fontWeight: isMe
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isMe ? _green : Colors.black87),
                        ),
                        Text('${q.from} в†’ ${q.to}',
                            style: TextStyle(
                                fontSize: AppText.labelSmall,
                                color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ]),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: q.seatsLeft > 0
                        ? _green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('рџ’є ${q.seatsLeft}',
                      style: TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: q.seatsLeft > 0 ? _green : Colors.red)),
                ),
              ]),
            );
          },
        ),
        if (nextRoute.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(children: [
              const Icon(Icons.swap_horiz, color: _orange, size: 16),
              const SizedBox(width: 6),
              Text('РљРµР№РёРЅРіРё РјР°СЂС€СЂСѓС‚: $nextRoute',
                  style: const TextStyle(
                      fontSize: AppText.bodySmall,
                      color: _orange,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}
