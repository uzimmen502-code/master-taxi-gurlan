import 'package:flutter/material.dart';

import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/domain/product_kind.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';

/// Админ: объект маҳсулотлари — рўйхат, таҳрирлаш, блоклаш, ўчириш (эга қарори 2026-10-24: эга ўзи жойлайди,
/// админ таҳрирлайди ва ўчиради). Ҳар ҳаракат серверда `admin_audit`га сабаби билан ёзилади (41-банд).
/// Матнлар Кирилл ёзувида қотирилган — бошқа админ экранлар каби.
class BusinessProductsAdminDialog extends StatefulWidget {
  const BusinessProductsAdminDialog({
    super.key,
    required this.business,
    required this.repo,
    TvShopRepository? shopRepository,
  }) : _shop = shopRepository;

  final Business business;
  final BusinessRepository repo;
  final TvShopRepository? _shop;

  @override
  State<BusinessProductsAdminDialog> createState() => _BusinessProductsAdminDialogState();
}

class _BusinessProductsAdminDialogState extends State<BusinessProductsAdminDialog> {
  late final TvShopRepository _shop = widget._shop ?? TvShopRepository();
  late Future<List<TvShopItem>> _future = _load();

  /// Эга фильтри йўқ (`ownerPhone` бўш): админ барча (ўчирилмаган) ҳужжатларни кўради.
  Future<List<TvShopItem>> _load() => _shop.fetchByBusiness(widget.business.id, onlyActive: false);

  void _reload() => setState(() {
        _future = _load();
      });

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit(TvShopItem it) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductEditDialog(item: it, repo: widget.repo),
    );
    if (done == true && mounted) {
      _snack('Сақланди');
      _reload();
    }
  }

  Future<void> _delete(TvShopItem it) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: 'Маҳсулотни ўчириш', body: '${it.title}\nЭга: ${it.ownerPhone}', confirm: 'Ўчириш'),
    );
    if (reason == null || !mounted) return;
    try {
      await widget.repo.adminDeleteProduct(it.id, reason: reason);
      if (!mounted) return;
      _snack('Ўчирилди');
      _reload();
    } catch (e) {
      if (mounted) _snack('Ўчириб бўлмади (${BusinessRepository.errorCode(e)})');
    }
  }

  static String _statusLabel(String s) => switch (s) {
        'active' => 'Фаол',
        'blocked' => 'Блокланган',
        'pending' => 'Кутилмоқда',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Маҳсулотлар · ${widget.business.name}'),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<TvShopItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return const Text('Юклаб бўлмади. Қайта уриниб кўринг.');
            if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            final items = snap.data!;
            if (items.isEmpty) return const Text('Маҳсулот йўқ.');
            return ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                return ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 44,
                    height: 44,
                    child: it.coverPhotoUrl.isEmpty
                        ? const Icon(Icons.image_not_supported_outlined)
                        : Image.network(it.coverPhotoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                  ),
                  title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    _statusLabel(it.status),
                    if (it.hasPrice) '${it.price} сўм',
                    if (it.hasVideo) 'видео бор',
                    'эга: ${it.ownerPhone}',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(tooltip: 'Таҳрирлаш', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(it)),
                      IconButton(
                        tooltip: 'Ўчириш',
                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                        onPressed: () => _delete(it),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш'))],
    );
  }
}

/// Сабаб (камида 3 белги) киритилмагунча тугма ўчиқ. Controller'ни диалогнинг ўзи бошқаради (`_DeleteDialog` каби).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.body, required this.confirm});

  final String title;
  final String body;
  final String confirm;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _reason.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('prod_admin_reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Сабаб (шарт)', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор қилиш')),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: Text(widget.confirm, style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
    );
  }
}

class _ProductEditDialog extends StatefulWidget {
  const _ProductEditDialog({required this.item, required this.repo});

  final TvShopItem item;
  final BusinessRepository repo;

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _price = TextEditingController(text: widget.item.price > 0 ? '${widget.item.price}' : '');
  late final _desc = TextEditingController(text: widget.item.description);
  final _reason = TextEditingController();
  late bool _blocked = widget.item.status == 'blocked';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _price, _desc, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().length < 3) return setState(() => _error = 'Сабабни ёзинг');
    if (_title.text.trim().length < 2) return setState(() => _error = 'Номини киритинг');
    final price = parseProductPrice(_price.text);
    if (price == null) return setState(() => _error = 'Нархни рақам билан киритинг');
    final it = widget.item;
    final title = _title.text.trim();
    final desc = _desc.text.trim();
    // Фақат ЎЗГАРГАН майдонлар юборилади — audit'да ҳақиқий ўзгаришлар кўринсин. `pending` ҳужжат фақат аниқ
    // блоклаш/очишда ўзгаради.
    final newStatus = _blocked ? 'blocked' : (it.status == 'blocked' ? 'active' : null);
    final titleChanged = title != it.title;
    final priceChanged = price != it.price;
    final descChanged = desc != it.description;
    final statusChanged = newStatus != null && newStatus != it.status;
    if (!(titleChanged || priceChanged || descChanged || statusChanged)) {
      return setState(() => _error = 'Ўзгариш йўқ');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.adminUpdateProduct(
        it.id,
        reason: _reason.text.trim(),
        title: titleChanged ? title : null,
        price: priceChanged ? price : null,
        description: descChanged ? desc : null,
        status: statusChanged ? newStatus : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Сақлаб бўлмади (${BusinessRepository.errorCode(e)})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Маҳсулотни таҳрирлаш'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(key: const ValueKey('prod_admin_title'), controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Номи', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('prod_admin_price'), controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Нарх, сўм', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('prod_admin_desc'), controller: _desc, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Тавсиф', border: OutlineInputBorder())),
              CheckboxListTile(
                key: const ValueKey('prod_admin_blocked'),
                value: _blocked,
                onChanged: _busy ? null : (v) => setState(() => _blocked = v ?? false),
                title: const Text('Блоклаш (бозорда кўринмайди)'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              TextField(key: const ValueKey('prod_admin_edit_reason'), controller: _reason, maxLength: 300, decoration: const InputDecoration(labelText: 'Таҳрир сабаби (шарт)', border: OutlineInputBorder())),
              if (_error != null) Align(alignment: Alignment.centerLeft, child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор қилиш')),
        FilledButton(
          key: const ValueKey('prod_admin_save'),
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Сақлаш'),
        ),
      ],
    );
  }
}
