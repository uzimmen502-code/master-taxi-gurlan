import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/procurement_product.dart';
import '../../../services/procurement_prices_service.dart';

/// Админ — `procurement_products` харид нархлари.
class ProcurementPricesScreen extends StatefulWidget {
  const ProcurementPricesScreen({super.key});

  @override
  State<ProcurementPricesScreen> createState() =>
      _ProcurementPricesScreenState();
}

class _ProcurementPricesScreenState extends State<ProcurementPricesScreen> {
  static const _blue = AppColors.primary;

  final _priceCtrls = <String, TextEditingController>{};
  bool _seeding = false;
  bool _saving = false;
  bool _bootstrapped = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapIfNeeded());
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrapIfNeeded() async {
    if (_bootstrapped) return;
    final service = context.read<ProcurementPricesService>();
    try {
      await service.ensureSeededIfEmpty();
      if (mounted) {
        setState(() {
          _bootstrapped = true;
          _bootError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapped = true;
          _bootError = e.toString();
        });
      }
    }
  }

  void _ensureControllers(List<ProcurementProduct> products) {
    for (final p in products) {
      _priceCtrls.putIfAbsent(
        p.code,
        () => TextEditingController(text: '${p.price}'),
      );
    }
  }

  int? _parsePrice(String code) {
    final raw = _priceCtrls[code]?.text.replaceAll(RegExp(r'\D'), '') ?? '';
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> _saveAll(List<ProcurementProduct> templates) async {
    final service = context.read<ProcurementPricesService>();
    final updated = <ProcurementProduct>[];
    for (final t in templates) {
      final price = _parsePrice(t.code);
      if (price == null || price < 0) {
        _snack('${t.label}: нархни тўғри киритинг', error: true);
        return;
      }
      updated.add(t.copyWith(price: price));
    }

    setState(() => _saving = true);
    try {
      await service.saveAll(updated);
      if (!mounted) return;
      _snack('Нархлар сақланди');
    } catch (e) {
      if (!mounted) return;
      _snack('Хатолик: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Стандарт нархларни тиклаш'),
        content: const Text(
          'Барча маҳсулот нархлари payment_products.dart '
          'стандарт қийматларига қайта ёзилади. Давом этасизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Тиклаш'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _seeding = true);
    final service = context.read<ProcurementPricesService>();
    try {
      await service.seedFromDefaults(overwrite: true);
      if (!mounted) return;
      for (final c in _priceCtrls.values) {
        c.dispose();
      }
      _priceCtrls.clear();
      _snack('Стандарт нархлар ёзилди');
    } catch (e) {
      if (!mounted) return;
      _snack('Хатолик: $e', error: true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : AppColors.button,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<ProcurementPricesService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                child: const Icon(Icons.price_change_outlined, color: _blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Харид нархлари',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'procurement_products · йиғиб олиш ва курьер тўлови',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _seeding || _saving ? null : _resetDefaults,
                icon: _seeding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore, size: 18),
                label: const Text('Стандарт нархларни тиклаш'),
              ),
            ],
          ),
        ),
        if (_bootError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Авто-seed хатоси: $_bootError',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<ProcurementProduct>>(
            stream: service.watchAll(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Хатолик: ${snap.error}'));
              }

              final products =
                  snap.data ?? ProcurementProduct.fromPaymentDefaults();
              _ensureControllers(products);

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      'Бу нархлар кейинчалик йиғиб олиш (collection) ва '
                      'курьер қабул қилган маҳсулот тўлови учун ишлатилади. '
                      'Коллекция бўш бўлса, оқиш payment_products.dart '
                      'стандартларига тушади.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...products.map((p) => _PriceRow(
                        product: p,
                        controller: _priceCtrls.putIfAbsent(
                          p.code,
                          () => TextEditingController(text: '${p.price}'),
                        ),
                        enabled: !_saving && !_seeding,
                      )),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving || _seeding
                        ? null
                        : () => _saveAll(products),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Сақланмоқда…' : 'Сақлаш'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.product,
    required this.controller,
    required this.enabled,
  });

  final ProcurementProduct product;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.code} · ${product.unit}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Нарх (сўм)',
                  suffixText: '/ ${product.unit}',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
