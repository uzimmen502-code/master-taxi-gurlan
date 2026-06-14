import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/courier_delivery_route_optimizer.dart';
import '../../../services/courier_route_service.dart';
import '../../../services/location_service.dart';
import '../controllers/courier_controller.dart';

const String _unknownMfyKey = '__unknown_mfy__';
const String _unknownMfyLabel = 'МФЙ аниқланмаган';

class _MfyGroup {
  const _MfyGroup({
    required this.key,
    required this.label,
    required this.orders,
  });

  final String key;
  final String label;
  final List<OrderModel> orders;
}

/// Kuryer marshrut qurishdan oldin faol (`ready`) buyurtmalardan MFY tanlash.
class CourierMfySelectionScreen extends StatefulWidget {
  const CourierMfySelectionScreen({super.key, this.ordersRepo});

  final OrdersRepository? ordersRepo;

  @override
  State<CourierMfySelectionScreen> createState() =>
      _CourierMfySelectionScreenState();
}

class _CourierMfySelectionScreenState extends State<CourierMfySelectionScreen> {
  static const Color _btn = AppColors.primaryDark;

  late final OrdersRepository _ordersRepo =
      widget.ordersRepo ?? OrdersRepository();
  final CourierDeliveryRouteOptimizer _optimizer =
      CourierDeliveryRouteOptimizer();
  final CourierRouteService _routeService = CourierRouteService();

  final Set<String> _selectedMfyKeys = {};
  bool _optimizing = false;
  String _loadingMessage = 'Маршрут ҳисобланмоқда...';
  List<OrderModel> _orderedStops = const [];

  List<_MfyGroup> _groupByMfy(List<OrderModel> orders) {
    final byMfy = <String, List<OrderModel>>{};
    final unknown = <OrderModel>[];

    for (final order in orders) {
      final mfy = order.mfy?.trim() ?? '';
      if (mfy.isEmpty) {
        unknown.add(order);
      } else {
        byMfy.putIfAbsent(mfy, () => []).add(order);
      }
    }

    final groups = <_MfyGroup>[];
    final sortedKeys = byMfy.keys.toList()..sort();
    for (final key in sortedKeys) {
      groups.add(_MfyGroup(
        key: key,
        label: key,
        orders: byMfy[key]!,
      ));
    }
    if (unknown.isNotEmpty) {
      groups.add(_MfyGroup(
        key: _unknownMfyKey,
        label: _unknownMfyLabel,
        orders: unknown,
      ));
    }
    return groups;
  }

  int _selectedOrderCount(List<_MfyGroup> groups) {
    var count = 0;
    for (final group in groups) {
      if (_selectedMfyKeys.contains(group.key)) {
        count += group.orders.length;
      }
    }
    return count;
  }

  List<OrderModel> _collectSelectedOrders(List<_MfyGroup> groups) {
    final selected = <OrderModel>[];
    for (final group in groups) {
      if (!_selectedMfyKeys.contains(group.key)) continue;
      selected.addAll(group.orders);
    }
    return selected;
  }

  /// Курьер жойлашуви — профил билан бир хил синалган йўл орқали:
  /// кэш (CourierController) → LocationService (last-known → medium → high).
  Future<LocationCoords?> _resolveCourierPosition() async {
    try {
      final courier = context.read<CourierController>();
      final cached = courier.currentPos;
      if (cached != null) {
        return LocationCoords(
          lat: cached.latitude,
          lng: cached.longitude,
          accuracy: cached.accuracy,
        );
      }
    } on ProviderNotFoundException {
      // MFY ekrani CourierController siz ham ochilishi mumkin (test).
    }

    try {
      // LocationService'нинг ўзи medium 5с / high 10с timeout +
      // getLastKnownPosition fallback'ига эга — қотиб қолмайди.
      return await const LocationService().getCurrentCoords();
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(Object error) {
    var message = error.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    } else if (message.startsWith('StateError: ')) {
      message = message.substring('StateError: '.length);
    }
    return message;
  }

  Future<String?> _resolveCourierPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone')?.trim() ?? '';
    return phone.isEmpty ? null : phone;
  }

  Future<void> _onBuildRoute(List<_MfyGroup> groups) async {
    if (_optimizing) return;

    final selectedOrders = _collectSelectedOrders(groups);
    if (selectedOrders.isEmpty) return;

    setState(() {
      _optimizing = true;
      _loadingMessage = 'Маршрут ҳисобланмоқда...';
    });

    try {
      final position = await _resolveCourierPosition();
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS аниқланмади — жойлашув рухсатини ёқинг'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final result = await _optimizer.optimize(
        originLat: position.lat,
        originLng: position.lng,
        orders: selectedOrders,
      );

      if (!mounted) return;

      setState(() => _orderedStops = result.orderedStops);

      debugPrint(
        'CourierMfySelection: optimizedOrderIds='
        '${_orderedStops.map((o) => o.id).toList()}',
      );

      if (result.skippedNoCoords > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.skippedNoCoords} та буюртма координатасиз — '
              'маршрутдан ўтказилди',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      if (_orderedStops.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Координатали буюртма қолмади'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final courierPhone = await _resolveCourierPhone();
      if (!mounted) return;
      if (courierPhone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Курьер телефони аниқланмади — қайта киринг'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() => _loadingMessage = 'Маршрут сақланмоқда...');

      final created = await _routeService.createRoute(
        courierPhone: courierPhone,
        orderedOrderIds: _orderedStops.map((o) => o.id).toList(),
      );

      if (!mounted) return;
      if (created.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(created.error!),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      try {
        await context.read<CourierController>().loadActiveRoute();
      } on ProviderNotFoundException {
        // Test / isolated screen.
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Маршрут яратилди: ${created.count} та тўхташ'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('МФЙ танлаш'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: _ordersRepo.watchReadyOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Хато: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          final orders = snapshot.data ?? const [];
          if (orders.isEmpty) {
            return Center(
              child: Text(
                'Фаол буюртма йўқ',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          final groups = _groupByMfy(orders);
          final selectedCount = _selectedOrderCount(groups);

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final isSelected = _selectedMfyKeys.contains(group.key);
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _optimizing
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedMfyKeys.remove(group.key);
                                      } else {
                                        _selectedMfyKeys.add(group.key);
                                      }
                                    });
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${group.label} — ${group.orders.length} та',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: AppColors.primary,
                                    onChanged: _optimizing
                                        ? null
                                        : (_) {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedMfyKeys
                                                    .remove(group.key);
                                              } else {
                                                _selectedMfyKeys.add(group.key);
                                              }
                                            });
                                          },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selectedCount == 0 || _optimizing
                              ? null
                              : () => _onBuildRoute(groups),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _btn,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Маршрут яратиш ($selectedCount та буюртма)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_optimizing)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                _loadingMessage,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
