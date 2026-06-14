import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart' as fmt;
import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../../shared/widgets/order_receipt_view.dart';
import '../../../services/admin_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin_web/services/admin_auth_service.dart';
import '../../admin_web/services/admin_orders_service.dart';

/// Админ учун — `orders` навбати (ҳолатни янгилаш).
///
/// `embedded: true` — Web админ shell (sidebar). PIN сессия етарли;
/// `AdminService` + `Navigator.pop()` shell'да глюч қилади.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key, this.embedded = false});

  /// Web админ панели sidebar'дан очилганда `true`.
  final bool embedded;

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  static const _blue = AppColors.primary;
  static final _money = NumberFormat.decimalPattern('en');
  static final _date = DateFormat('dd.MM HH:mm');

  bool _adminChecked = false;
  bool _isAdmin = false;
  String? _busyOrderId;
  String? _bulkBusyColumn;
  final ScrollController _boardScrollController = ScrollController();

  static const _columns = [
    _OrderColumnSpec(
      status: 'new',
      title: 'Янги',
      color: Colors.deepOrange,
    ),
    _OrderColumnSpec(
      status: 'accepted',
      title: 'Қабул',
      color: Colors.blue,
    ),
    _OrderColumnSpec(
      status: 'ready',
      title: 'Тайёр',
      color: Colors.purple,
    ),
    _OrderColumnSpec(
      status: 'in_delivery',
      title: 'Курьерда',
      color: Colors.indigo,
    ),
    _OrderColumnSpec(
      status: 'delivered',
      title: 'Етказилди',
      color: AppColors.primary,
    ),
    _OrderColumnSpec(
      status: 'rejected',
      title: 'Рад қилинган',
      color: Colors.red,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    if (widget.embedded) {
      if (!mounted) return;
      setState(() {
        _isAdmin = true;
        _adminChecked = true;
      });
      return;
    }

    bool ok = false;
    try {
      ok = await context.read<AdminService>().isCurrentUserAdmin();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = ok;
      _adminChecked = true;
    });
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⛔ Сизда буюртмаларни бошқариш ҳуқуқи йўқ'),
          ),
        );
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  List<String>? _nextActions(String status, OrderFlowModes flow) {
    switch (status) {
      case 'new':
        if (flow.acceptAuto) return const ['rejected'];
        return const ['accepted', 'rejected'];
      case 'accepted':
        if (flow.readyAuto) return const ['rejected'];
        return const ['ready', 'rejected'];
      case 'ready':
        return const ['in_delivery'];
      case 'in_delivery':
      case 'courier':
        return const ['delivered'];
      default:
        return null;
    }
  }

  String _actionLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'in_delivery':
        return 'Курьерда';
      case 'delivered':
        return 'Етказилди';
      case 'rejected':
        return 'Рад этиш';
      default:
        return s;
    }
  }

  String _columnStatus(String s) {
    if (s == 'courier') return 'in_delivery';
    if (s == 'cancelled') return 'rejected';
    return s;
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'new':
        return Colors.deepOrange;
      case 'accepted':
        return Colors.blue;
      case 'ready':
        return Colors.purple;
      case 'in_delivery':
      case 'courier':
        return Colors.indigo;
      case 'delivered':
        return AppColors.primary;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.red.shade300;
      default:
        return Colors.grey;
    }
  }

  String _statusUz(String s) {
    switch (s) {
      case 'new':
        return 'Янги';
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'in_delivery':
      case 'courier':
        return 'Курьерда';
      case 'delivered':
        return 'Етказилди';
      case 'rejected':
        return 'Рад қилинган';
      case 'cancelled':
        return 'Рад қилинган';
      default:
        return s;
    }
  }

  String _typeUz(String t) {
    switch (t) {
      case 'food':
        return 'Овқат';
      case 'bread':
      default:
        return 'Нон';
    }
  }

  /// Ustun boshidagi bulk tugmalar.
  List<_BulkActionSpec>? _columnBulkActions(
    String columnStatus,
    OrderFlowModes flow,
  ) {
    switch (columnStatus) {
      case 'new':
        if (flow.acceptAuto) return null;
        return const [
          _BulkActionSpec(status: 'accepted', label: 'Қабул', positive: true),
          _BulkActionSpec(status: 'rejected', label: 'Рад', positive: false),
        ];
      case 'accepted':
        if (flow.readyAuto) return null;
        return const [
          _BulkActionSpec(status: 'ready', label: 'Тайёр', positive: true),
        ];
      case 'ready':
        return const [
          _BulkActionSpec(
            status: 'in_delivery',
            label: 'Курьерда',
            positive: true,
          ),
        ];
      case 'in_delivery':
        return const [
          _BulkActionSpec(
            status: 'delivered',
            label: 'Етказилди',
            positive: true,
          ),
        ];
      default:
        return null;
    }
  }

  Future<void> _applyBulkStatus({
    required List<OrderModel> orders,
    required String next,
    required String columnTitle,
  }) async {
    if (orders.isEmpty || _bulkBusyColumn != null) return;

    final label = _actionLabel(next);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('«$columnTitle» — $label'),
        content: Text(
          '${orders.length} ta буюртма «$label» holatiga oʻtkazilsinmi?\n\n'
          'Har bir mijozga xabar yuboriladi (Хабарлар → Буюртма).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkBusyColumn = columnTitle);
    try {
      final ok = await _setStatusBatch(
        orders.map((o) => o.id).toList(growable: false),
        next,
      );
      if (!ok || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${orders.length} ta buyurtma — $label'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хатолик: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusyColumn = null);
    }
  }

  Future<String?> _adminPhoneForCf() async {
    if (!widget.embedded) return null;

    String? raw;
    try {
      final auth = context.read<AdminAuthService>();
      if (auth.phoneDigits != null && auth.phoneDigits!.isNotEmpty) {
        raw = auth.phoneDigits;
      } else if (auth.phone != null && auth.phone!.isNotEmpty) {
        raw = auth.phone;
      }
    } catch (_) {}

    if (raw == null || fmt.phoneDigits(raw).length < 9) {
      final prefs = await SharedPreferences.getInstance();
      raw ??= prefs.getString('admin_web_phone');
      raw ??= prefs.getString('user_phone');
    }

    final digits = fmt.phoneDigits(raw ?? '');
    return digits.length >= 9 ? digits : null;
  }

  Future<bool> _setStatus(String orderId, String status) async {
    if (widget.embedded) {
      final adminPhone = await _adminPhoneForCf();
      if (adminPhone == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Админ телефони аниқланмади — қайта киринг'),
            ),
          );
        }
        return false;
      }
      final err = await AdminOrdersService().setOrderStatus(
        adminPhone: adminPhone,
        orderId: orderId,
        status: status,
      );
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(err),
            ),
          );
        }
        return false;
      }
      return true;
    }
    await context.read<OrdersRepository>().setOrderStatus(orderId, status);
    return true;
  }

  Future<bool> _setStatusBatch(List<String> orderIds, String status) async {
    if (widget.embedded) {
      final adminPhone = await _adminPhoneForCf();
      if (adminPhone == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Админ телефони аниқланмади — қайта киринг'),
            ),
          );
        }
        return false;
      }
      final err = await AdminOrdersService().setOrderStatusBatch(
        adminPhone: adminPhone,
        orderIds: orderIds,
        status: status,
      );
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(err),
            ),
          );
        }
        return false;
      }
      return true;
    }
    await context.read<OrdersRepository>().setOrderStatusBatch(orderIds, status);
    return true;
  }

  Future<void> _applyStatus(String orderId, String next) async {
    if (_bulkBusyColumn != null) return;
    setState(() => _busyOrderId = orderId);
    try {
      final ok = await _setStatus(orderId, next);
      if (!ok || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${_actionLabel(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Хато: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  void dispose() {
    _boardScrollController.dispose();
    super.dispose();
  }

  Widget _deniedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text(
              'Буюртмаларни бошқариш ҳуқуқи йўқ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Админ панелга қайта киринг ёки Firestore\'da role=admin '
              'эканлигини текширинг.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.view_kanban_outlined, color: _blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Буюртмалар устунларда. Устун боши — барча буюртма; '
                    'карта — бittasi alohida.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
              stream: context
                  .read<OrdersRepository>()
                  .watchRecentOrders(limit: 100),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Хато: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final orders = snap.data!;
                if (orders.isEmpty) {
                  return const Center(
                    child: Text(
                      'Буюртмалар йўқ',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return StreamBuilder<OrderFlowModes>(
                  stream: context.read<OrdersRepository>().watchOrderFlowModes(),
                  builder: (context, flowSnap) {
                    final flow = flowSnap.data ?? const OrderFlowModes();

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        const minColumnWidth = 280.0;
                        final minBoardWidth = minColumnWidth * _columns.length;
                        final boardWidth =
                            math.max(constraints.maxWidth, minBoardWidth);
                        final boardHeight =
                            math.max(0.0, constraints.maxHeight - 24);

                        return Scrollbar(
                          controller: _boardScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _boardScrollController,
                            padding: const EdgeInsets.all(12),
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: boardWidth,
                              height: boardHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final column in _columns)
                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 10),
                                        child: _OrdersColumn(
                                          spec: column,
                                          flow: flow,
                                          orders: orders
                                              .where((o) =>
                                                  _columnStatus(o.status) ==
                                                  column.status)
                                              .toList(growable: false),
                                          busyOrderId: _busyOrderId,
                                          bulkBusy: _bulkBusyColumn != null,
                                          bulkActions: _columnBulkActions(
                                            column.status,
                                            flow,
                                          ),
                                          onBulkAction: (next) =>
                                              _applyBulkStatus(
                                            orders: orders
                                                .where((o) =>
                                                    _columnStatus(o.status) ==
                                                    column.status)
                                                .toList(growable: false),
                                            next: next,
                                            columnTitle: column.title,
                                          ),
                                          nextActions: (s) =>
                                              _nextActions(s, flow),
                                          statusColor: _statusColor,
                                          statusUz: _statusUz,
                                          typeUz: _typeUz,
                                          money: _money,
                                          date: _date,
                                          actionLabel: _actionLabel,
                                          onAction: _applyStatus,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked) {
      return const ColoredBox(
        color: AppColors.scaffold,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return ColoredBox(
        color: AppColors.scaffold,
        child: _deniedBody(),
      );
    }

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.scaffold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                '📦 Буюртмалар',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(child: _boardContent()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(
          '📦 Буюртмалар',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _boardContent(),
    );
  }
}

class _OrderColumnSpec {
  const _OrderColumnSpec({
    required this.status,
    required this.title,
    required this.color,
  });

  final String status;
  final String title;
  final Color color;
}

class _BulkActionSpec {
  const _BulkActionSpec({
    required this.status,
    required this.label,
    required this.positive,
  });

  final String status;
  final String label;
  final bool positive;
}

class _OrdersColumn extends StatelessWidget {
  const _OrdersColumn({
    required this.spec,
    required this.flow,
    required this.orders,
    required this.busyOrderId,
    required this.bulkBusy,
    required this.bulkActions,
    required this.onBulkAction,
    required this.nextActions,
    required this.statusColor,
    required this.statusUz,
    required this.typeUz,
    required this.money,
    required this.date,
    required this.actionLabel,
    required this.onAction,
  });

  final _OrderColumnSpec spec;
  final OrderFlowModes flow;
  final List<OrderModel> orders;
  final String? busyOrderId;
  final bool bulkBusy;
  final List<_BulkActionSpec>? bulkActions;
  final Future<void> Function(String next) onBulkAction;
  final List<String>? Function(String status) nextActions;
  final Color Function(String status) statusColor;
  final String Function(String status) statusUz;
  final String Function(String type) typeUz;
  final NumberFormat money;
  final DateFormat date;
  final String Function(String status) actionLabel;
  final void Function(String orderId, String next) onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: spec.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    spec.title,
                    style: TextStyle(
                      color: spec.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: TextStyle(
                      color: spec.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (spec.status == 'accepted' || spec.status == 'ready')
            _OrderColumnModeBar(
              columnStatus: spec.status,
              flow: flow,
              color: spec.color,
            ),
          if (bulkActions != null && bulkActions!.isNotEmpty && orders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: bulkBusy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final action in bulkActions!)
                          SizedBox(
                            height: 34,
                            child: FilledButton.tonal(
                              style: action.positive
                                  ? FilledButton.styleFrom(
                                      backgroundColor:
                                          spec.color.withValues(alpha: 0.15),
                                      foregroundColor: spec.color,
                                    )
                                  : FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade50,
                                      foregroundColor: Colors.red.shade700,
                                    ),
                              onPressed: bulkBusy || busyOrderId != null
                                  ? null
                                  : () => onBulkAction(action.status),
                              child: Text(
                                '${action.label} (${orders.length})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      'Бўш',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    itemBuilder: (ctx, i) {
                      final o = orders[i];
                      return _OrderCard(
                        order: o,
                        busy: busyOrderId == o.id || bulkBusy,
                        next: nextActions(o.status),
                        statusColor: statusColor(o.status),
                        statusUz: statusUz(o.status),
                        typeUz: typeUz(o.type),
                        money: money,
                        date: date,
                        actionLabel: actionLabel,
                        onAction: onAction,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Қабул / Тайёр устуни: автомат ёки қўлда (bulk тугмалардан юқорида).
class _OrderColumnModeBar extends StatefulWidget {
  const _OrderColumnModeBar({
    required this.columnStatus,
    required this.flow,
    required this.color,
  });

  final String columnStatus;
  final OrderFlowModes flow;
  final Color color;

  @override
  State<_OrderColumnModeBar> createState() => _OrderColumnModeBarState();
}

class _OrderColumnModeBarState extends State<_OrderColumnModeBar> {
  bool _saving = false;

  bool get _isAuto => widget.columnStatus == 'accepted'
      ? widget.flow.acceptAuto
      : widget.flow.readyAuto;

  String get _hint => widget.columnStatus == 'accepted'
      ? (_isAuto
          ? 'Янги буюртмалар автомат қабул қилинади'
          : 'Админ «Қабул» тугмасини ўзи босади')
      : (_isAuto
          ? 'Қабул қилинган буюртмалар автомат тайёр бўлади'
          : 'Админ «Тайёр» тугмасини ўзи босади');

  Future<void> _setMode(bool auto) async {
    if (_saving) return;
    final next = auto ? 'auto' : 'manual';
    final current =
        widget.columnStatus == 'accepted' ? widget.flow.accept : widget.flow.ready;
    if (current == next) return;

    setState(() => _saving = true);
    try {
      final repo = context.read<OrdersRepository>();
      if (widget.columnStatus == 'accepted') {
        await repo.setOrderAcceptMode(next);
      } else {
        await repo.setOrderReadyMode(next);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Режим сақланмади: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Режим',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.back_hand_outlined, size: 16),
                  label: Text('Қўлда', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.flash_on, size: 16),
                  label: Text('Авто', style: TextStyle(fontSize: 11)),
                ),
              ],
              selected: {_isAuto},
              onSelectionChanged: (s) => _setMode(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            _hint,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.next,
    required this.statusColor,
    required this.statusUz,
    required this.typeUz,
    required this.money,
    required this.date,
    required this.actionLabel,
    required this.onAction,
  });

  final OrderModel order;
  final bool busy;
  final List<String>? next;
  final Color statusColor;
  final String statusUz;
  final String typeUz;
  final NumberFormat money;
  final DateFormat date;
  final String Function(String) actionLabel;
  final void Function(String orderId, String next) onAction;

  @override
  Widget build(BuildContext context) {
    final when = order.createdAt != null ? date.format(order.createdAt!) : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusUz,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  typeUz,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  when,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OrderReceiptView(
              order: order,
              title: '🧾 Чек · ${money.format(order.total)} сўм',
            ),
            if (next != null && next!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final s in next!)
                    FilledButton.tonal(
                      style: s == 'rejected'
                          ? FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red.shade700,
                            )
                          : null,
                      onPressed: busy ? null : () => onAction(order.id, s),
                      child: Text(actionLabel(s)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
