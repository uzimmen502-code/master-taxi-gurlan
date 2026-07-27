import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';

/// Админ: платформа дўкони каталоги.
class PlatformProductsAdminScreen extends StatefulWidget {
  const PlatformProductsAdminScreen({super.key});

  @override
  State<PlatformProductsAdminScreen> createState() =>
      _PlatformProductsAdminScreenState();
}

class _PlatformProductsAdminScreenState
    extends State<PlatformProductsAdminScreen> {
  final _repo = PlatformProductsRepository();

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : AppColors.button,
      ),
    );
  }

  Future<void> _openEdit([PlatformProduct? existing]) async {
    final result = await showDialog<PlatformProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      if (existing == null) {
        await _repo.create(result);
        _toast('Қўшилди');
      } else {
        await _repo.update(result);
        _toast('Сақланди');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  Future<void> _delete(PlatformProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш'),
        content: Text('«${p.name}» ўчирилсинми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(p.id);
      if (!mounted) return;
      _toast('Ўчирилди');
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        backgroundColor: AppColors.button,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Маҳсулот'),
      ),
      body: StreamBuilder<List<PlatformProduct>>(
        stream: _repo.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Каталог бўш — маҳсулот қўшинг'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = items[i];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: _Thumb(url: p.imageUrl),
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      '${formatPrice(p.price)} сўм',
                      p.active ? 'фаол' : 'нофаол',
                      if (p.featuredOnHome) 'витрина',
                      if (p.showInMarket) 'бозор',
                      p.isUnlimitedStock
                          ? 'лимитсиз'
                          : 'қолдиқ ${p.remaining}',
                    ].join(' · '),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await _openEdit(p);
                      } else if (v == 'toggle') {
                        await _repo.setActive(p.id, !p.active);
                      } else if (v == 'delete') {
                        await _delete(p);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Таҳрир'),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(p.active ? 'Нофаол' : 'Фаол'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Ўчириш'),
                      ),
                    ],
                  ),
                  onTap: () => _openEdit(p),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    Widget child = const ColoredBox(
      color: Color(0xFFE8F5E9),
      child: Icon(Icons.storefront, color: AppColors.button),
    );
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      child = CachedNetworkImage(imageUrl: u, fit: BoxFit.cover);
    } else if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) child = Image.memory(bytes, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 48, height: 48, child: child),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});

  final PlatformProduct? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _sort;
  late bool _active;
  late bool _featured;
  late bool _inMarket;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _image = TextEditingController(text: e?.imageUrl ?? '');
    _unit = TextEditingController(text: e?.unit ?? 'дона');
    _stock = TextEditingController(
      text: e != null ? '${e.totalStock}' : '0',
    );
    _sort = TextEditingController(text: e != null ? '${e.sortOrder}' : '0');
    _active = e?.active ?? true;
    _featured = e?.featuredOnHome ?? false;
    _inMarket = e?.showInMarket ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _image.dispose();
    _unit.dispose();
    _stock.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim()) ?? -1;
    if (name.isEmpty || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ном ва нарх мажбурий')),
      );
      return;
    }
    final existing = widget.existing;
    Navigator.pop(
      context,
      PlatformProduct(
        id: existing?.id ?? '',
        name: name,
        description: _desc.text.trim(),
        price: price,
        imageUrl: _image.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'дона' : _unit.text.trim(),
        minQty: existing?.minQty ?? 1,
        step: existing?.step ?? 1,
        totalStock: int.tryParse(_stock.text.trim()) ?? 0,
        soldToday: existing?.soldToday ?? 0,
        active: _active,
        featuredOnHome: _featured,
        showInMarket: _inMarket,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Янги маҳсулот' : 'Таҳрир'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Ном'),
              ),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Тавсиф'),
                maxLines: 2,
              ),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Нарх (сўм)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _image,
                decoration: const InputDecoration(labelText: 'Расм URL'),
              ),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Бирлик'),
              ),
              TextField(
                controller: _stock,
                decoration: const InputDecoration(
                  labelText: 'Омбор (0 = лимитсиз)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _sort,
                decoration: const InputDecoration(labelText: 'Тартиб'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тавсия этамиз (витрина)'),
                value: _featured,
                onChanged: (v) => setState(() => _featured = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Онлайн бозорда кўрсатиш'),
                value: _inMarket,
                onChanged: (v) => setState(() => _inMarket = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}
