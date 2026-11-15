import 'package:flutter/material.dart';

import '../../tv_market/domain/price_unit.dart';
import '../utils/listing_moderation.dart';

/// «Тузатиш ва тасдиқлаш» (эга 2026-11-15): админ эълонни тузатади — сарлавҳа, тавсиф, нарх, бирлик, бўлим,
/// расмларни олиб ташлаш. Натижа — фақат ўзгарган майдонлар (`edits`; бўш бўлса — оддий тасдиқ);
/// бекор — `null`. Текширув [buildListingEdits] (сервер `validateListingEdits` билан бир хил қоидалар).
Future<Map<String, Object?>?> showListingEditDialog(
  BuildContext context,
  ListingModItem item, {
  List<ListingModCategory> categories = const [],
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => ListingEditDialog(item: item, categories: categories),
  );
}

class ListingEditDialog extends StatefulWidget {
  const ListingEditDialog({super.key, required this.item, this.categories = const []});

  final ListingModItem item;

  /// Шу бозор бўлимлари (`taxonomy/markets`); бўш — фақат матн майдони.
  final List<ListingModCategory> categories;

  @override
  State<ListingEditDialog> createState() => _ListingEditDialogState();
}

class _ListingEditDialogState extends State<ListingEditDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.item.title);
  late final TextEditingController _description = TextEditingController(text: widget.item.description);
  late final TextEditingController _price = TextEditingController(text: '${widget.item.price}');
  late final TextEditingController _category = TextEditingController(text: widget.item.categoryValue);
  late String _unit = PriceUnit.fromWire(widget.item.priceUnit).wire;
  late final Set<String> _removed = <String>{};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  void _submit() {
    final r = buildListingEdits(
      widget.item,
      title: _title.text,
      description: _description.text,
      priceText: _price.text,
      priceUnit: _unit,
      category: _category.text,
      keptPhotos: [for (final u in widget.item.photoUrls) if (!_removed.contains(u)) u],
    );
    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    Navigator.of(context).pop(r.edits);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final hasMarket = it.market.isNotEmpty;
    return AlertDialog(
      title: const Text('Тузатиш ва тасдиқлаш'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (it.rejectReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Рад этиш сабаби: ${it.rejectReason}', style: TextStyle(color: Colors.red.shade700)),
              ),
            TextField(
              key: const ValueKey('ledit_title'),
              controller: _title,
              maxLength: kListingTitleMax,
              decoration: const InputDecoration(labelText: 'Сарлавҳа'),
            ),
            TextField(
              key: const ValueKey('ledit_description'),
              controller: _description,
              maxLength: kListingDescriptionMax,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Тавсиф'),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ledit_price'),
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Нарх (сўм)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('ledit_unit'),
                  initialValue: _unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Нарх бирлиги'),
                  items: [
                    for (final u in PriceUnit.values)
                      DropdownMenuItem(
                        value: u.wire,
                        child: Text(kListingPriceUnitLabels[u] ?? u.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? ''),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (hasMarket) ...[
              TextField(
                key: const ValueKey('ledit_category'),
                controller: _category,
                maxLength: kListingCategoryMax,
                decoration: InputDecoration(labelText: 'Бўлим (${it.market})'),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.categories.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in widget.categories)
                    ChoiceChip(
                      key: ValueKey('ledit_cat_${c.id}'),
                      label: Text(c.name),
                      selected: _category.text.trim() == c.id,
                      onSelected: (_) => setState(() => _category.text = c.id),
                    ),
                ]),
              const SizedBox(height: 8),
            ],
            if (it.photoUrls.isNotEmpty) ...[
              const Text('Расмлар (олиб ташлаш учун босинг)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < it.photoUrls.length; i++) _photo(i, it.photoUrls[i]),
              ]),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, key: const ValueKey('ledit_error'), style: TextStyle(color: Colors.red.shade700)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Бекор')),
        FilledButton.icon(
          key: const ValueKey('ledit_submit'),
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Тасдиқлаш'),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
        ),
      ],
    );
  }

  Widget _photo(int i, String url) {
    final removed = _removed.contains(url);
    return InkWell(
      key: ValueKey('ledit_photo_$i'),
      onTap: () => setState(() => removed ? _removed.remove(url) : _removed.add(url)),
      child: Stack(children: [
        Opacity(
          opacity: removed ? 0.3 : 1,
          child: SizedBox(
            width: 84,
            height: 84,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0x11000000), child: Icon(Icons.broken_image_outlined))),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: Icon(
            removed ? Icons.undo : Icons.delete_outline,
            size: 20,
            color: removed ? Colors.blueGrey : Colors.red.shade700,
          ),
        ),
      ]),
    );
  }
}
