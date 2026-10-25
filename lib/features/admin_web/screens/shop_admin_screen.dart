import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import 'business_products_admin_dialog.dart';

/// Админ: онлайн дўконлар (эга қарори 2026-10-25: «админ назорати барча кириш йўлларида»).
///
/// Битта сотувчининг ягона онлайн дўкони (`tv_shops/{phone}`), унинг йўналиш дўконлари (`businesses`) ва
/// маҳсулотлари (`tv_shop_items`) — бир экранда: блоклаш/очиш (бутун дўкон ёки битта йўналиш), маҳсулотларни
/// таҳрирлаш/блоклаш/ўчириш. Пастда — энг сўнгги маҳсулотлар (барча ҳолатда): шикоят келган маҳсулотни топиш учун.
/// Ҳар ҳаракат серверда сабаби билан `admin_audit`га ёзилади (41-банд). Матнлар Кирилл ёзувида қотирилган.
class ShopAdminScreen extends StatefulWidget {
  const ShopAdminScreen({super.key, BusinessRepository? repository, TvShopRepository? shopRepository})
      : _repo = repository,
        _shop = shopRepository;

  final BusinessRepository? _repo;
  final TvShopRepository? _shop;

  @override
  State<ShopAdminScreen> createState() => _ShopAdminScreenState();
}

class _ShopAdminScreenState extends State<ShopAdminScreen> {
  late final BusinessRepository _repo = widget._repo ?? BusinessRepository();
  late final TvShopRepository _shop = widget._shop ?? TvShopRepository();
  final _phone = TextEditingController();

  String _owner = '';
  TvShop? _shopDoc;
  List<Business> _businesses = const [];
  bool _loadingOwner = false;
  String? _ownerError;
  late Future<List<TvShopItem>> _recent = _shop.fetchRecentAll();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openOwner([String? raw]) async {
    final id = canonicalPhoneId(raw ?? _phone.text);
    if (id.length != 12) {
      setState(() => _ownerError = 'Телефон рақамини тўлиқ киритинг (998XXXXXXXXX)');
      return;
    }
    if (raw != null) _phone.text = id;
    setState(() {
      _owner = id;
      _loadingOwner = true;
      _ownerError = null;
    });
    try {
      final results = await Future.wait([_shop.fetchShop(id), _repo.fetchByOwner(id)]);
      if (!mounted || _owner != id) return;
      setState(() {
        _shopDoc = results[0] as TvShop?;
        _businesses = results[1] as List<Business>;
        _loadingOwner = false;
      });
    } catch (e) {
      debugPrint('[ShopAdmin] $e');
      if (!mounted) return;
      setState(() {
        _loadingOwner = false;
        _ownerError = 'Юклаб бўлмади. Қайта уриниб кўринг.';
      });
    }
  }

  Future<String?> _askReason({required String title, required String body, required String confirm}) =>
      showDialog<String>(
        context: context,
        builder: (_) => AdminReasonDialog(title: title, body: body, confirm: confirm),
      );

  Future<void> _toggleShop() async {
    final block = !(_shopDoc?.isBlocked ?? false);
    final reason = await _askReason(
      title: block ? 'Онлайн дўконни блоклаш' : 'Дўконни блокдан чиқариш',
      body: block
          ? 'Эга: $_owner\n\nБарча йўналишлари харитадан йўқолади, барча фаол маҳсулотлари блокланади, '
              'эга янги маҳсулот ва йўналиш қўша олмайди. Видеолар АВАГрамда қолади.'
          : 'Эга: $_owner\n\nШу блок билан ёпилган йўналиш ва маҳсулотлар очилади '
              '(алоҳида блокланганлари блокланган қолади).',
      confirm: block ? 'Блоклаш' : 'Очиш',
    );
    if (reason == null || !mounted) return;
    try {
      await _repo.adminSetShopStatus(_owner, status: block ? 'blocked' : 'active', reason: reason);
      _snack(block ? 'Дўкон блокланди' : 'Дўкон очилди');
      await _openOwner(_owner);
    } catch (e) {
      _snack(adminActionError(e, fallback: block ? 'Блоклаб бўлмади' : 'Очиб бўлмади'));
    }
  }

  Future<void> _toggleBusiness(Business b) async {
    final block = !b.isBlocked;
    final reason = await _askReason(
      title: block ? 'Йўналишни блоклаш' : 'Йўналишни блокдан чиқариш',
      body: block
          ? '${b.name}\n\nХаритадан йўқолади, барча фаол маҳсулотлари блокланади.'
          : '${b.name}\n\nХаритага қайтади, шу блок билан ёпилган маҳсулотлари очилади.',
      confirm: block ? 'Блоклаш' : 'Очиш',
    );
    if (reason == null || !mounted) return;
    try {
      final n = await _repo.adminSetStatus(b.id, status: block ? 'blocked' : 'active', reason: reason);
      _snack(block ? 'Блокланди (маҳсулот: $n)' : 'Очилди (маҳсулот: $n)');
      await _openOwner(_owner);
    } catch (e) {
      _snack(adminActionError(e, fallback: block ? 'Блоклаб бўлмади' : 'Очиб бўлмади'));
    }
  }

  Future<void> _products(Business b) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BusinessProductsAdminDialog(business: b, repo: _repo, shopRepository: _shop),
    );
    if (mounted) _reloadRecent();
  }

  void _reloadRecent() => setState(() {
        _recent = _shop.fetchRecentAll();
      });

  static String _statusLabel(String s) => switch (s) {
        'active' => 'Фаол',
        'blocked' => 'Блокланган',
        'pending' => 'Кутилмоқда',
        'deleted' => 'Ўчирилган',
        _ => s,
      };

  Widget _statusChip(bool blocked) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(blocked ? 'Блокланган' : 'Фаол'),
        backgroundColor: blocked ? Colors.red.shade50 : Colors.green.shade50,
        side: BorderSide(color: blocked ? Colors.red.shade200 : Colors.green.shade200),
      );

  Widget _ownerPanel() {
    if (_owner.isEmpty) return const SizedBox.shrink();
    if (_loadingOwner) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2));
    final shopBlocked = _shopDoc?.isBlocked ?? false;
    final shopName = (_shopDoc?.name ?? '').trim();
    final main = Business.ownShop(ownerId: _owner, name: shopName.isEmpty ? _owner : shopName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const ValueKey('shop_admin_main'),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: ListTile(
            leading: Icon(Icons.storefront_rounded, color: shopBlocked ? Colors.red.shade700 : null),
            title: Text(shopName.isEmpty ? 'Номсиз онлайн дўкон' : shopName),
            subtitle: Text(_shopDoc == null
                ? 'Эга: $_owner · дўкон ҳужжати йўқ (фақат йўналишлари ёки маҳсулотлари бўлиши мумкин)'
                : 'Эга: $_owner · асосий дўкон ва ${_businesses.length} та йўналиш'),
            trailing: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _statusChip(shopBlocked),
                IconButton(
                  key: const ValueKey('shop_admin_main_products'),
                  tooltip: 'Асосий дўкон маҳсулотлари',
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => _products(main),
                ),
                IconButton(
                  key: const ValueKey('shop_admin_shop_block'),
                  tooltip: shopBlocked ? 'Дўконни блокдан чиқариш' : 'Бутун дўконни блоклаш',
                  icon: Icon(shopBlocked ? Icons.lock_open_rounded : Icons.block_rounded, color: Colors.red.shade700),
                  onPressed: _toggleShop,
                ),
              ],
            ),
          ),
        ),
        for (final b in _businesses)
          Card(
            margin: const EdgeInsets.fromLTRB(28, 0, 12, 6),
            child: ListTile(
              dense: true,
              leading: Icon(b.isBlocked ? Icons.block_rounded : b.category.icon,
                  color: b.isBlocked ? Colors.red.shade700 : null),
              title: Text(b.name),
              subtitle: Text([if (b.address.isNotEmpty) b.address, 'тел: ${b.phone}'].join(' · ')),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _statusChip(b.isBlocked),
                  IconButton(
                    tooltip: 'Маҳсулотлар',
                    icon: const Icon(Icons.inventory_2_outlined),
                    onPressed: () => _products(b),
                  ),
                  IconButton(
                    key: ValueKey('shop_admin_biz_block_${b.id}'),
                    tooltip: b.isBlocked ? 'Йўналишни блокдан чиқариш' : 'Йўналишни блоклаш',
                    icon: Icon(b.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded),
                    onPressed: () => _toggleBusiness(b),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _recentList() => FutureBuilder<List<TvShopItem>>(
        future: _recent,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Padding(padding: EdgeInsets.all(16), child: Text('Юклаб бўлмади. Қайта уриниб кўринг.'));
          }
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2));
          final items = snap.data!;
          if (items.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Маҳсулот йўқ'));
          return Column(
            children: [
              for (final it in items)
                ListTile(
                  key: ValueKey('shop_admin_recent_${it.id}'),
                  dense: true,
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: it.coverPhotoUrl.isEmpty
                        ? const Icon(Icons.image_not_supported_outlined)
                        : Image.network(it.coverPhotoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                  ),
                  title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    _statusLabel(it.status),
                    if (it.hasPrice) '${it.price} сўм',
                    it.businessId.isEmpty ? 'асосий дўкон' : 'йўналиш',
                    'эга: ${it.ownerPhone}',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openOwner(it.ownerPhone),
                ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏪 Онлайн дўконлар', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Янгилаш',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _reloadRecent();
              if (_owner.isNotEmpty) _openOwner(_owner);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('shop_admin_phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    onSubmitted: (_) => _openOwner(),
                    decoration: InputDecoration(
                      hintText: 'Сотувчи телефони (998XXXXXXXXX)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _ownerError,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('shop_admin_open'),
                  onPressed: () => _openOwner(),
                  child: const Text('Очиш'),
                ),
              ],
            ),
          ),
          _ownerPanel(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Энг сўнгги маҳсулотлар (барча ҳолатда, 100 тагача) — босинг: шу сотувчи дўкони очилади',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          _recentList(),
        ],
      ),
    );
  }
}
