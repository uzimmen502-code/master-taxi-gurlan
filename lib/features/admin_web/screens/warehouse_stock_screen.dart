import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/collection_service.dart';
import '../../../services/procurement_prices_service.dart';
import '../services/admin_auth_service.dart';

/// Админ — омбор (`warehouse_stock`) ҳолати. Read-only.
///
/// Қолдиқлар фақат курьер йиғишни якунлаганда (collection finalize) ўзгаради,
/// бу ерда таҳрирлаш йўқ. Маълумот Admin SDK Cloud Function орқали ўқилади.
class WarehouseStockScreen extends StatefulWidget {
  const WarehouseStockScreen({super.key});

  @override
  State<WarehouseStockScreen> createState() => _WarehouseStockScreenState();
}

class _WarehouseStockScreenState extends State<WarehouseStockScreen> {
  static const _blue = AppColors.primary;

  bool _loading = true;
  String? _error;
  List<WarehouseStockItem> _items = const [];
  Map<String, int> _prices = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _adminPhoneForCf() {
    final auth = context.read<AdminAuthService>();
    if (auth.phoneDigits != null && auth.phoneDigits!.isNotEmpty) {
      return auth.phoneDigits!;
    }
    final d = phoneDigits(auth.phone ?? '');
    return d.length >= 9 ? d : '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final adminPhone = _adminPhoneForCf();
    if (adminPhone.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Admin telefon topilmadi — qayta kiring';
      });
      return;
    }
    try {
      final results = await Future.wait([
        CollectionService.getWarehouseStock(adminPhone: adminPhone),
        _loadPrices(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<WarehouseStockItem>;
        _prices = results[1] as Map<String, int>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Нархлар (қиймат устуни учун). Хато бўлса — бўш харита, қиймат «—» бўлади.
  Future<Map<String, int>> _loadPrices() async {
    try {
      final products = await ProcurementPricesService().getAll();
      return {for (final p in products) p.code: p.price};
    } catch (_) {
      return const {};
    }
  }

  int? _rowValue(WarehouseStockItem item) {
    final price = _prices[item.code];
    if (price == null) return null;
    return (item.quantity * price).round();
  }

  int get _grandTotal {
    var total = 0;
    for (final item in _items) {
      final v = _rowValue(item);
      if (v != null) total += v;
    }
    return total;
  }

  bool get _hasAnyValue => _items.any((i) => _rowValue(i) != null);

  String _qtyText(num qty) {
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.warehouse_outlined, color: _blue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Омбор',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'warehouse_stock · курьер йиққан маҳсулот қолдиқлари',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Янгилаш'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
              const SizedBox(height: 12),
              Text(
                'Хатолик: $_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Қайта уриниш'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Омборда маҳсулот йўқ',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _tableHeader(),
        const SizedBox(height: 8),
        ..._items.map(_stockCard),
        if (_hasAnyValue) ...[
          const SizedBox(height: 12),
          _grandTotalCard(),
        ],
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(
        'Бу қолдиқлар фақат курьер маҳсулот йиғишни якунлаганда ўзгаради. '
        'Бу ерда таҳрирлаш йўқ — фақат кузатиш. Қиймат = миқдор × харид нархи '
        '(нарх йўқ бўлса «—»).',
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Colors.blue.shade900,
        ),
      ),
    );
  }

  Widget _stockCard(WarehouseStockItem item) {
    final value = _rowValue(item);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label.isNotEmpty ? item.label : item.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Охирги янгиланиш: ${formatDateShort(item.updatedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Миқдор',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    '${_qtyText(item.quantity)} ${item.unit}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Қиймат',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    value != null ? '${formatPrice(value)} сўм' : '—',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: value != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grandTotalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Жами қиймат:',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            '${formatPrice(_grandTotal)} сўм',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
