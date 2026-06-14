import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/order_model.dart';
import 'courier_payment_sheet.dart';

class CourierOrderTile extends StatelessWidget {
  const CourierOrderTile({
    super.key,
    required this.order,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    this.needsFinalize = false,
    required this.onPicked,
    required this.onArrived,
    required this.onPayment,
    required this.onFinalizeRoute,
  });

  final OrderModel order;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final bool needsFinalize;
  final Future<void> Function() onPicked;
  final Future<void> Function() onArrived;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> lines)
      onPayment;
  final Future<void> Function() onFinalizeRoute;

  static const Color _blue = AppColors.primary;
  static const Color _green = AppColors.primaryDark;

  Future<void> _call() async {
    if (order.userPhone.isEmpty) return;
    final url = Uri.parse('tel:${phoneForCall(order.userPhone)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigate() async {
    if (!order.hasCoordinates) return;
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${order.lat},${order.lng}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openPayment(BuildContext context) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => CourierPaymentSheet(
        order: order,
        onSubmit: onPayment,
      ),
    ).whenComplete(() => onFinalizeRoute());
  }

  bool get _canSubmitPayment =>
      order.effectiveFulfillment == 'arrived' &&
      order.effectivePayment != 'paid';

  bool get _isFinalized =>
      order.effectivePayment == 'paid' ||
      order.effectiveFulfillment == 'completed';

  String _statusLabel(BuildContext context) {
    if (_isFinalized) return context.tr('courier_status_done');
    switch (order.effectiveFulfillment) {
      case 'courier_picked':
        return context.tr('courier_status_en_route');
      case 'arrived':
        return context.tr('courier_status_arrived');
      case 'completed':
        return context.tr('courier_status_done');
      default:
        return context.tr('courier_status_waiting');
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsPreview = order.items
        .take(2)
        .map((e) => '${e.name} ×${e.count}')
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDone ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? Colors.grey.shade200
              : isCurrent
                  ? _green
                  : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _indexBadge(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.userName.isNotEmpty
                            ? order.userName
                            : order.userPhone,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDone
                              ? Colors.grey.shade400
                              : Colors.black87,
                        ),
                      ),
                      Text(
                        order.address,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  _statusLabel(context),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDone ? Colors.grey : _green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$itemsPreview · ${formatPrice(order.total)} ${context.tr('currency_sum')}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (needsFinalize) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async => onFinalizeRoute(),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    context.tr('courier_next_order'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else if (isCurrent) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _smallButton(
                      icon: Icons.call,
                      label: context.tr('courier_call'),
                      color: _blue,
                      onTap: _call,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _smallButton(
                      icon: Icons.navigation,
                      label: context.tr('courier_navigate'),
                      color: _blue,
                      onTap: _navigate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildActionButtonsRow(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtonsRow(BuildContext context) {
    final chips = <Widget>[];
    if (order.canCourierPick) {
      chips.add(_actionChip(context.tr('courier_pick'), onPicked));
    }
    if (order.canCourierArrive) {
      chips.add(_actionChip(context.tr('courier_arrived_btn'), onArrived));
    }
    if (_canSubmitPayment) {
      chips.add(
        _actionChip(
          context.tr('courier_pay_btn'),
          () => _openPayment(context),
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }

  Widget _actionChip(String label, Future<void> Function() onTap) {
    return FilledButton.tonal(
      onPressed: () async => onTap(),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _indexBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isDone
            ? Colors.grey.shade300
            : isCurrent
                ? _green
                : Colors.orange.shade100,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDone
                ? Colors.grey
                : isCurrent
                    ? Colors.white
                    : _blue,
          ),
        ),
      ),
    );
  }

  Widget _smallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
