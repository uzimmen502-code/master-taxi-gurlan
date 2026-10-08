import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/order_model.dart';
import '../../../repositories/orders_repository.dart';

/// Админ тарихи чегараси: [from]дан олдин яратилган якунланган буюртма
/// админ устунларида яширилади (базадан ўчирилмайди). Фаол буюртма
/// санадан қатъи назар кўринади — осилиб қолган буюртма кўздан йўқолмасин.
bool isHiddenByOrderHistoryFrom(OrderModel order, DateTime? from) {
  if (from == null || !order.hasFinalStatus) return false;
  final created = order.createdAt;
  return created != null && created.isBefore(from);
}

/// «Буюртмалар» ва «Курьер» бўлимлари учун умумий тарих панели.
/// Сана `settings/app.adminOrderHistoryFrom`да — барча админлар учун битта.
class OrderHistoryFromBar extends StatefulWidget {
  const OrderHistoryFromBar({super.key, required this.from});

  final DateTime? from;

  @override
  State<OrderHistoryFromBar> createState() => _OrderHistoryFromBarState();
}

class _OrderHistoryFromBarState extends State<OrderHistoryFromBar> {
  static final _day = DateFormat('dd.MM.yyyy');
  static final _firstDate = DateTime(2020);

  bool _saving = false;

  Future<void> _save(DateTime? from) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<OrdersRepository>().setAdminOrderHistoryFrom(from);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Санани сақлаб бўлмади. Қайта уриниб кўринг.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final current = widget.from;
    final initial = current == null ||
            current.isAfter(now) ||
            current.isBefore(_firstDate)
        ? now
        : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _firstDate,
      lastDate: now,
      helpText: 'Шу санадан олдинги тарих яширилсин',
    );
    if (picked == null || !mounted) return;
    await _save(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.from;
    final text = from == null
        ? 'Тарих: барча якунланган буюртмалар кўринмоқда'
        : 'Тарих: ${_day.format(from)} дан олдинги якунланган буюртмалар '
            'яширилган (базада сақланади)';

    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          children: [
            Icon(Icons.history, size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              TextButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.event, size: 18),
                label: Text(from == null ? 'Санани танлаш' : 'Ўзгартириш'),
              ),
              if (from != null)
                TextButton(
                  onPressed: () => _save(null),
                  child: const Text('Ҳаммасини кўрсатиш'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
