import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/user_error.dart';
import '../../../models/order_model.dart';
import '../../../services/courier_delivery_route_optimizer.dart';
import '../../../services/courier_route_service.dart';
import '../../../services/location_service.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../controllers/courier_controller.dart';

const String _unknownMfyKey = '__unknown_mfy__';

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
///
/// Рўйхат — `courierListReadyOrders` callable (фақат id/МФЙ/координата).
/// Аввал `orders where status == 'ready'` оқими эди: `courier` `isStaff()`дан
/// чиқарилгач (D-SERVICE-4 / D-CLEAN-1) қоида уни capability курьерга рад
/// этади, очиш эса ҳар бир курьерга бутун буюртма ҳужжатини берарди.
class CourierMfySelectionScreen extends StatefulWidget {
  const CourierMfySelectionScreen({super.key, this.routeService, this.locate});

  final CourierRouteService? routeService;

  /// Курьер GPS'и (D-GEO-3: GPS + 15 км) — стандарт рухсат сўрамайдиган
  /// [LocationService.getCoordsIfAllowed]; тестда алмаштирилади.
  final Future<LocationCoords?> Function()? locate;

  @override
  State<CourierMfySelectionScreen> createState() =>
      _CourierMfySelectionScreenState();
}

class _CourierMfySelectionScreenState extends State<CourierMfySelectionScreen> {
  static const Color _btn = AppColors.primaryDark;

  final CourierDeliveryRouteOptimizer _optimizer =
      CourierDeliveryRouteOptimizer();
  late final CourierRouteService _routeService =
      widget.routeService ?? CourierRouteService();
  late Future<List<OrderModel>> _readyOrders = _loadReady();

  /// GPS бўлса — радиус ичидагилар (сервер филтри); йўқ бўлса ҳаммаси.
  Future<List<OrderModel>> _loadReady() async {
    final locate = widget.locate ?? const LocationService().getCoordsIfAllowed;
    final c = await locate();
    return _routeService.listReadyOrders(lat: c?.lat, lng: c?.lng);
  }

  /// Рўйхатни қайта олиш: pull-to-refresh ва маршрут яратилмаганда
  /// (буюртмани бошқа курьер олиб улгурган бўлиши мумкин).
  Future<void> _reload() async {
    final next = _loadReady();
    setState(() {
      _readyOrders = next;
    });
    try {
      await next;
    } catch (_) {
      // Хато FutureBuilder'да кўрсатилади.
    }
  }

  /// Бўш ёки хато ҳолатда ҳам pull-to-refresh ишласин.
  Widget _refreshable(Widget child) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(child: child),
            ),
          ],
        ),
      ),
    );
  }

  final Set<String> _selectedMfyKeys = {};
  bool _optimizing = false;
  /// l10n kaliti (ekranda `context.tr` bilan chiqadi).
  String _loadingMessage = 'crr_route_calculating';
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
        label: context.tr('crr_mfy_unknown'),
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
      _loadingMessage = 'crr_route_calculating';
    });

    try {
      final position = await _resolveCourierPosition();
      if (!mounted) return;
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('crr_gps_unknown')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Optimizer koordinatali buyurtma topolmasa `StateError` tashlaydi
      // (kirill matn). Xabarni shu yerda l10n bilan beramiz.
      if (!selectedOrders.any(CourierDeliveryRouteOptimizer.hasValidCoords)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('crr_route_no_coords')),
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
              context.trMsg('crr_route_skipped_no_coords',
                  params: {'n': '${result.skippedNoCoords}'}),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      if (_orderedStops.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('crr_route_no_coords_left')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final courierPhone = await _resolveCourierPhone();
      if (!mounted) return;
      if (courierPhone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('crr_phone_unknown')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() => _loadingMessage = 'crr_route_saving');

      final created = await _routeService.createRoute(
        courierPhone: courierPhone,
        orderedOrderIds: _orderedStops.map((o) => o.id).toList(),
      );

      if (!mounted) return;
      if (created.error != null) {
        // Servis xabari (`no_ready_orders`, inglizcha yoki kirill literal)
        // foydalanuvchiga chiqmaydi — faqat logga.
        debugPrint('CourierMfySelection: createRoute error: ${created.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr(created.error == 'no_ready_orders'
                ? 'crr_route_orders_taken'
                : 'crr_route_create_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _reload();
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
          content: Text(context.trMsg('crr_route_created',
              params: {'n': '${created.count}'})),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              userErrorMessage(context, e, fallbackKey: 'crr_route_create_failed')),
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
        title: Text(context.tr('crr_mfy_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: FutureBuilder<List<OrderModel>>(
        future: _readyOrders,
        builder: (context, snapshot) {
          // Қайта олишда эски рўйхат/хато кўриниб туради (FutureBuilder
          // уни сақлайди) — спиннер фақат биринчи юкланишда.
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData &&
              !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _refreshable(
              LoadErrorView(
                error: snapshot.error!,
                onRetry: () => _reload(),
              ),
            );
          }

          final orders = snapshot.data ?? const [];
          if (orders.isEmpty) {
            return _refreshable(
              Text(
                context.tr('crr_no_active_orders'),
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
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final isSelected =
                              _selectedMfyKeys.contains(group.key);
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
                                        context.trMsg('crr_mfy_group_count',
                                            params: {
                                              'label': group.label,
                                              'n': '${group.orders.length}',
                                            }),
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
                                                  _selectedMfyKeys
                                                      .add(group.key);
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
                            foregroundColor: AppColors.onPrimary,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            context.trMsg('crr_route_create_btn',
                                params: {'n': '$selectedCount'}),
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
                                context.tr(_loadingMessage),
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
