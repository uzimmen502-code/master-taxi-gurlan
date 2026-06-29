import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/data_url_image.dart';
import '../../../models/bread_extra_product.dart';
import '../../../models/bread_product.dart';
import '../../../models/food_product.dart';
import '../../../repositories/bread_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../bread/services/bread_image_storage.dart';
import '../../../core/theme/app_theme.dart';

/// РњР°ТіСЃСѓР»oС‚ РјРµРЅРµР¶РµСЂРё вЂ” РЅРѕРЅ, С‚Р°РѕРј РєР°С‚Р°Р»РѕРі (`food_catalog` + СЂР°СЃРјР»Р°СЂ), Т›СћС€РёРјС‡Р° РјР°ТіСЃСѓР»РѕС‚Р»Р°СЂ.
class ProductsManagerScreen extends StatefulWidget {
  const ProductsManagerScreen({super.key});

  @override
  State<ProductsManagerScreen> createState() => _ProductsManagerScreenState();
}

class _ProductsManagerScreenState extends State<ProductsManagerScreen>
    with SingleTickerProviderStateMixin {
  // Phase-3 decommission switch: hide Food tab in admin UI.
  static const bool _enableFoodTab = true;

  late final TabController _tabCtrl;
  late final List<String> _tabKeys =
      _enableFoodTab ? const ['bread', 'food', 'extra'] : const ['bread', 'extra'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabKeys.length, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(text: 'рџ«“ РќoРЅ'),
      if (_enableFoodTab) const Tab(text: 'рџЌЅ РўР°РѕРј'),
      const Tab(text: 'рџЊї ТљСћС€РёРјС‡a'),
    ];
    final tabViews = <Widget>[
      const _BreadProductsTab(),
      if (_enableFoodTab) const _FoodProductsTab(),
      const _ExtraProductsTab(),
    ];

    return Column(children: [
      _header(),
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: tabs,
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: tabViews,
        ),
      ),
    ]);
  }

  String get _currentTabKey {
    final i = _tabCtrl.index;
    if (i < 0 || i >= _tabKeys.length) return _tabKeys.first;
    return _tabKeys[i];
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        const Text('рџ“¦ РњР°ТіСЃСѓР»oС‚Р»aСЂ',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton.icon(
            onPressed: _openAdd,
            icon: const Icon(Icons.add),
            label: const Text('РЇРЅРіРё РјaТіСЃСѓР»oС‚'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
      ]),
    );
  }

  Future<void> _openAdd() async {
    if (_currentTabKey == 'bread') {
      await _openBreadEditor(context, null);
    } else if (_currentTabKey == 'extra') {
      await _openExtraEditor(context, null);
    } else if (_currentTabKey == 'food') {
      await _openFoodEditor(context, null);
    }
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// BREAD TAB
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

class _BreadProductsTab extends StatelessWidget {
  const _BreadProductsTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<BreadRepository>();
    return StreamBuilder<List<BreadProduct>>(
      stream: repo.watchProducts(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _empty(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'РҐР°С‚oР»РёРє',
            msg: 'Р®РєР»aР± Р±СћР»РјaРґРё: ${snap.error}',
          );
        }
        final items = snap.data ?? const <BreadProduct>[];
        if (items.isEmpty) {
          return _empty(
            icon: Icons.inventory_2_outlined,
            color: Colors.grey,
            title: 'РќoРЅ Т›СћС€РёР»РјaРіaРЅ',
            msg: 'Р®Т›oСЂРё СћРЅРіРґaРіРё "+ РЇРЅРіРё РјaТіСЃСѓР»oС‚" С‚СѓРіРјaСЃРёРЅРё Р±oСЃРёРЅРі.',
          );
        }
        return LayoutBuilder(builder: (lctx, constraints) {
          final pad = constraints.maxWidth > 800 ? 24.0 : 12.0;
          final cols = (constraints.maxWidth / 320).floor().clamp(1, 4);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 310,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _BreadCard(item: items[i]),
          );
        });
      },
    );
  }
}

class _BreadCard extends StatelessWidget {
  const _BreadCard({required this.item});
  final BreadProduct item;

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('РЋС‡РёСЂРёС€РЅРё С‚aСЃРґРёТ›Р»aРЅРі'),
        content: Text('"${item.name}" РЅoРЅРёРЅРё СћС‡РёСЂРёС€РЅРё С…oТіР»aР№cРёР·РјРё?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Р‘РµРєoСЂ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('РЋС‡РёСЂРёС€', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await context
          .read<BreadRepository>()
          .deleteProduct(item.firestoreId ?? '');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.button,
            content: Text('рџ—‘ "${item.name}" СћС‡РёСЂРёР»РґРё')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    }
  }

  Future<void> _resetSold(BuildContext context) async {
    try {
      await context
          .read<BreadRepository>()
          .resetProductSold(item.firestoreId ?? '');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.blue,
            content: Text('рџ”„ "${item.name}" СЃoС‚РёР»РіaРЅ = 0')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = item.isYopish
        ? AppColors.primary
        : item.isToy
            ? AppColors.primary
            : AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: typeColor.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Center(child: _image()),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(item.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(item.type,
                      style: TextStyle(
                          fontSize: 10,
                          color: typeColor,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 6),
              if (item.price != null && item.price! > 0)
                Text('${item.price} СЃСћРј',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              const SizedBox(height: 4),
              _stockBar(),
              const Spacer(),
              Row(children: [
                IconButton(
                  onPressed: () => _resetSold(context),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'РЎoС‚РёР»РіaРЅ = 0',
                  color: Colors.blue.shade600,
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openBreadEditor(context, item),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Tahrir'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary),
                ),
                IconButton(
                  onPressed: () => _delete(context),
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: Colors.red.shade400),
                  tooltip: 'РЋС‡РёСЂРёС€',
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _image() {
    final mem = decodeDataUrlImageBytes(item.imageUrl);
    if (mem != null && mem.isNotEmpty) {
      return Image.memory(
        mem,
        height: 90,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Text(item.emoji, style: const TextStyle(fontSize: 56)),
      );
    }
    if (item.imageUrl.isNotEmpty && isHttpImageUrl(item.imageUrl)) {
      return CachedNetworkImage(
        imageUrl: item.imageUrl.trim(),
        height: 90,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) =>
            Text(item.emoji, style: const TextStyle(fontSize: 56)),
        placeholder: (_, __) => const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Text(item.emoji, style: const TextStyle(fontSize: 56));
  }

  Widget _stockBar() {
    if (item.totalStock <= 0) {
      return Text('Р›РёРјРёС‚СЃРёР·',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500));
    }
    final ratio = (item.soldToday / item.totalStock).clamp(0.0, 1.0);
    final color = ratio > 0.85
        ? Colors.red
        : ratio > 0.6
            ? Colors.orange
            : Colors.green;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('${item.soldToday} / ${item.totalStock}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        const Spacer(),
        Text('ТљoР»РґРё: ${item.remaining}',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 4,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// FOOD CATALOG TAB (Firestore `food_catalog`, СЂР°СЃРј + РЅР°СЂС… / Р·Р°С…РёСЂР°)
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

class _FoodProductsTab extends StatelessWidget {
  const _FoodProductsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('food_catalog')
          .orderBy('id')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _empty(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'РҐР°С‚oР»РёРє',
            msg: 'food_catalog: ${snap.error}',
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restaurant_menu,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 14),
                  const Text(
                    'РўР°РѕРј РјР°ТіСЃСѓР»РѕС‚Р»Р°СЂРё FirestoreКјРґР° Р№СћТ›.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bir martalik Cloud Function \'seedFoodCatalog\' ni chaqing '
                    'yoki konsoldan \'food_catalog\' ga ТіСѓР¶Р¶Р°С‚ Т›СћС€РёРЅРі.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (_, constraints) {
            final pad = constraints.maxWidth > 800 ? 24.0 : 12.0;
            return GridView.builder(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                childAspectRatio: 1.05,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final docSnap = docs[i];
                final product =
                    FoodProduct.fromFirestore(docSnap.data(), docSnap.id);
                return _FoodProductCard(
                  key: ValueKey(docSnap.id),
                  product: product,
                  docId: docSnap.id,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FoodProductCard extends StatefulWidget {
  const _FoodProductCard({
    super.key,
    required this.product,
    required this.docId,
  });
  final FoodProduct product;
  final String docId;

  @override
  State<_FoodProductCard> createState() => _FoodProductCardState();
}

class _FoodProductCardState extends State<_FoodProductCard> {
  bool _uploading = false;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.product.price.toString());
  }

  @override
  void didUpdateWidget(_FoodProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.price != widget.product.price) {
      _priceCtrl.text = widget.product.price.toString();
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final res = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          )
          .timeout(const Duration(minutes: 3));

      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Р¤Р°Р№Р» СћТ›РёР»РјР°РґРё вЂ” РєРёС‡РёРєСЂРѕТ› JPG/PNG С‚Р°РЅР»Р°РЅРі.'),
            ),
          );
        }
        return;
      }
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Р Р°СЃРј 2 MB РґР°РЅ РєРёС‡РёРє Р±СћР»СЃРёРЅ.'),
            ),
          );
        }
        return;
      }

      final name = (f.name).toLowerCase();
      final String mime;
      if (name.endsWith('.png')) {
        mime = 'image/png';
      } else if (name.endsWith('.webp')) {
        mime = 'image/webp';
      } else {
        mime = 'image/jpeg';
      }

      final storage = BreadImageStorage();
      final url = await storage.uploadFoodImage(
        docId: widget.docId,
        bytes: bytes,
        contentType: mime,
      );

      await FirebaseFirestore.instance
          .collection('food_catalog')
          .doc(widget.docId)
          .update({'imageUrl': url});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('Р Р°СЃРј СЋРєР»Р°РЅРґРё'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚o: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _savePrice() async {
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) return;
    try {
      await FirebaseFirestore.instance
          .collection('food_catalog')
          .doc(widget.docId)
          .update({'price': price});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('РќР°СЂС… СЃР°Т›Р»Р°РЅРґРё'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('$e')),
      );
    }
  }

  Future<void> _resetSold() async {
    try {
      await context.read<InventoryRepository>().setStock(
            kind: InventoryKind.food,
            id: widget.product.inventoryId,
            soldToday: 0,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blue,
          content: Text('рџ”„ "${widget.product.name}" вЂ” СЃРѕС‚РёР»РіР°РЅ = 0'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    }
  }

  Future<void> _editStockDoc() async {
    final snap = await FirebaseFirestore.instance
        .collection('food_inventory')
        .doc(widget.product.inventoryId)
        .get();
    FoodInventoryDoc? existing;
    final d = snap.data();
    if (d != null) {
      existing = FoodInventoryDoc(
        totalStock: (d['totalStock'] as num?)?.toInt() ?? 0,
        soldToday: (d['soldToday'] as num?)?.toInt() ?? 0,
      );
    }
    if (!mounted) return;
    await _openFoodStockEditor(context, widget.product, existing);
  }

  Future<void> _openEditor() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FoodProductEditorDialog(
        product: widget.product,
        docId: widget.docId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _uploading ? null : _pickAndUpload,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(
                  color: Colors.grey.shade100,
                  child: p.imageUrl.isNotEmpty && isHttpImageUrl(p.imageUrl)
                      ? CachedNetworkImage(
                          imageUrl: p.imageUrl.trim(),
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (_, __, ___) => Center(
                              child: Text(p.emoji,
                                  style: const TextStyle(fontSize: 48))),
                        )
                      : Center(
                          child: Text(p.emoji,
                              style: const TextStyle(fontSize: 52)),
                        ),
                ),
                if (_uploading)
                  const ColoredBox(
                    color: Color(0x88000000),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.name} В· ${p.category}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          border: OutlineInputBorder(),
                          suffixText: 'СЃСћРј',
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _savePrice,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                      child: const Icon(Icons.check, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _editStockDoc,
                        icon: const Icon(Icons.inventory_2, size: 16),
                        label: const Text('Р—Р°С…РёСЂР°',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'РЎРѕС‚РёР»РіР°РЅ = 0',
                      onPressed: _resetSold,
                      icon: Icon(Icons.refresh,
                          size: 20, color: Colors.blue.shade700),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('РўР°ТіСЂРёСЂ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodProductEditorDialog extends StatefulWidget {
  const _FoodProductEditorDialog({
    required this.product,
    required this.docId,
  });

  final FoodProduct product;
  final String docId;

  @override
  State<_FoodProductEditorDialog> createState() =>
      _FoodProductEditorDialogState();
}

class _FoodProductEditorDialogState extends State<_FoodProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _emoji;
  late final TextEditingController _price;
  late final TextEditingController _unit;
  late final TextEditingController _minQty;
  late final TextEditingController _step;
  late final TextEditingController _category;
  late final TextEditingController _desc;
  late final TextEditingController _imageUrl;
  late final TextEditingController _totalStock;
  bool _busy = false;
  bool _uploading = false;
  int _soldToday = 0;

  FoodProduct get product => widget.product;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: product.name);
    _emoji = TextEditingController(text: product.emoji);
    _price = TextEditingController(text: product.price.toString());
    _unit = TextEditingController(text: product.unit);
    _minQty = TextEditingController(text: _numText(product.minQty));
    _step = TextEditingController(text: _numText(product.step));
    _category = TextEditingController(text: product.category);
    _desc = TextEditingController(text: product.desc);
    _imageUrl = TextEditingController(text: product.imageUrl);
    _totalStock = TextEditingController(text: '0');
    _loadStock();
  }

  static String _numText(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _loadStock() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('food_inventory')
          .doc(product.inventoryId)
          .get();
      final d = snap.data();
      if (d == null || !mounted) return;
      _totalStock.text = ((d['totalStock'] as num?)?.toInt() ?? 0).toString();
      _soldToday = (d['soldToday'] as num?)?.toInt() ?? 0;
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _price.dispose();
    _unit.dispose();
    _minQty.dispose();
    _step.dispose();
    _category.dispose();
    _desc.dispose();
    _imageUrl.dispose();
    _totalStock.dispose();
    super.dispose();
  }

  String _mimeForName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final res = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          )
          .timeout(const Duration(minutes: 3));
      if (res == null || res.files.isEmpty) return;

      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Р¤Р°Р№Р» СћТ›РёР»РјР°РґРё вЂ” РєРёС‡РёРєСЂРѕТ› JPG/PNG С‚Р°РЅР»Р°РЅРі.'),
          ),
        );
        return;
      }
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Р Р°СЃРј 2 MB РґР°РЅ РєРёС‡РёРє Р±СћР»СЃРёРЅ.'),
          ),
        );
        return;
      }

      final url = await BreadImageStorage().uploadFoodImage(
        docId: widget.docId,
        bytes: bytes,
        contentType: _mimeForName(f.name),
      );
      _imageUrl.text = url;
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚o: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.red, content: Text('РќРѕРј Р±СћС€ Р±СћР»Р° РѕР»РјР°Р№РґРё')),
      );
      return;
    }
    final price = int.tryParse(_price.text.trim()) ?? 0;
    final minQty =
        double.tryParse(_minQty.text.trim().replaceAll(',', '.')) ?? 1;
    final step = double.tryParse(_step.text.trim().replaceAll(',', '.')) ?? 1;
    final totalStock = int.tryParse(_totalStock.text.trim()) ?? 0;
    final inventoryRepo = context.read<InventoryRepository>();

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('food_catalog')
          .doc(widget.docId)
          .set({
        'id': product.id,
        'name': name,
        'emoji': _emoji.text.trim().isEmpty ? 'рџЌЅ' : _emoji.text.trim(),
        'price': price,
        'unit': _unit.text.trim().isEmpty ? 'РєРі' : _unit.text.trim(),
        'minQty': minQty,
        'step': step,
        'category': _category.text.trim(),
        'desc': _desc.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await inventoryRepo.setStock(
        kind: InventoryKind.food,
        id: product.inventoryId,
        totalStock: totalStock,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('рџЌЅ "$name" СЃР°Т›Р»Р°РЅРґРё'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚o: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogW = (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 620.0);
    return AlertDialog(
      title: Text('рџЌЅ ${product.name}'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _foodImagePreview(_imageUrl, product.emoji, height: 190),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: (_busy || _uploading) ? null : _pickAndUpload,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_uploading ? 'Р®РєР»Р°РЅРјРѕТ›РґР°...' : 'Р Р°СЃРј С‚Р°РЅР»Р°С€'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    flex: 3,
                    child: _field(_name, 'РќРѕРј',
                        icon: Icons.short_text, maxLen: 80)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_emoji, 'Emoji',
                        icon: Icons.emoji_food_beverage, maxLen: 6)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _field(_price, 'РќР°СЂС…',
                      icon: Icons.attach_money,
                      keyboard: TextInputType.number,
                      digits: true,
                      maxLen: 8),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_unit, 'Р‘РёСЂР»РёРє',
                        icon: Icons.straighten, maxLen: 20)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _field(_minQty, 'РњРёРЅРёРјСѓРј',
                        icon: Icons.exposure,
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                        maxLen: 8)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_step, 'ТљР°РґР°Рј',
                        icon: Icons.add,
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                        maxLen: 8)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_totalStock, 'Р—Р°С…РёСЂР°',
                        icon: Icons.inventory_2,
                        keyboard: TextInputType.number,
                        digits: true,
                        helper: '0 = Р»РёРјРёС‚СЃРёР·',
                        maxLen: 6)),
              ]),
              if (_soldToday > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Р‘СѓРіСѓРЅ СЃРѕС‚РёР»РіР°РЅ: $_soldToday',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
              const SizedBox(height: 10),
              _field(_category, 'РљР°С‚РµРіРѕСЂРёСЏ', icon: Icons.category, maxLen: 40),
              const SizedBox(height: 10),
              _field(_desc, 'РўР°РІСЃРёС„',
                  icon: Icons.notes, maxLen: 300, maxLines: 3),
              const SizedBox(height: 10),
              _field(_imageUrl, 'Р Р°СЃРј URL',
                  icon: Icons.link, maxLen: 4096, maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Р‘РµРєРѕСЂ'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('РЎР°Т›Р»Р°С€'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

Widget _foodImagePreview(
  TextEditingController imageUrl,
  String fallbackEmoji, {
  double height = 160,
}) {
  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: imageUrl,
    builder: (context, value, _) {
      final raw = value.text.trim();
      Widget child;
      if (raw.isNotEmpty && isHttpImageUrl(raw)) {
        child = Image.network(
          raw,
          fit: BoxFit.cover,
          width: double.infinity,
          height: height,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          loadingBuilder: (context, imageChild, progress) {
            if (progress == null) return imageChild;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (_, __, ___) => Center(
              child: Text(fallbackEmoji, style: const TextStyle(fontSize: 54))),
        );
      } else {
        child = Center(
          child: Text(
            fallbackEmoji.trim().isEmpty ? 'рџЌЅ' : fallbackEmoji.trim(),
            style: const TextStyle(fontSize: 56),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: height,
          width: double.infinity,
          color: Colors.grey.shade100,
          child: child,
        ),
      );
    },
  );
}

Future<void> _openFoodStockEditor(
  BuildContext context,
  FoodProduct product,
  FoodInventoryDoc? existing,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) =>
        _FoodStockEditorDialog(product: product, existing: existing),
  );
}

class _FoodStockEditorDialog extends StatefulWidget {
  const _FoodStockEditorDialog({
    required this.product,
    this.existing,
  });

  final FoodProduct product;
  final FoodInventoryDoc? existing;

  @override
  State<_FoodStockEditorDialog> createState() => _FoodStockEditorDialogState();
}

class _FoodStockEditorDialogState extends State<_FoodStockEditorDialog> {
  late final TextEditingController _totalStock;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _totalStock = TextEditingController(text: (e?.totalStock ?? 0).toString());
  }

  @override
  void dispose() {
    _totalStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = int.tryParse(_totalStock.text.trim()) ?? 0;
    if (v < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Р—Р°С…РёСЂР° РјР°РЅС„РёР№ Р±СћР»Р° РѕР»РјР°Р№РґРё'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<InventoryRepository>().setStock(
            kind: InventoryKind.food,
            id: widget.product.inventoryId,
            totalStock: v,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('рџЌ± "${widget.product.name}" Р·Р°С…РёСЂР°СЃРё СЃР°Т›Р»Р°РЅРґРё'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sold = widget.existing?.soldToday ?? 0;
    final dialogW = (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 420.0);
    return AlertDialog(
      title: Text('рџЌ± ${widget.product.name}'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'РќР°СЂС… РІР° РЅРѕРј РєР°С‚Р°Р»РѕРіРґР° (РєРѕРґ). Р‘Сѓ РµСЂРґР° С„Р°Т›Р°С‚ Firestore '
                '`food_inventory/${widget.product.inventoryId}` Р·Р°С…РёСЂР°СЃРё.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              Text('Р‘СѓРіСѓРЅ СЃРѕС‚РёР»РіР°РЅ (РєРі)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800)),
              const SizedBox(height: 4),
              Text('$sold',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 14),
              _field(
                _totalStock,
                'Р–Р°РјРё Р·Р°С…РёСЂР° (РєРі)',
                icon: Icons.inventory_2,
                keyboard: TextInputType.number,
                digits: true,
                maxLen: 6,
                helper: '0 = Р»РёРјРёС‚СЃРёР· (РёР»РѕРІР°РґР° С‚РµРєС€РёСЂРёР»РјР°Р№РґРё)',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Р‘РµРєoСЂ'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('РЎaТ›Р»aС€'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// EXTRAS TAB
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

class _ExtraProductsTab extends StatelessWidget {
  const _ExtraProductsTab();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<BreadRepository>();
    return StreamBuilder<List<BreadExtraProduct>>(
      stream: repo.watchExtraProducts(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _empty(
            icon: Icons.error_outline,
            color: Colors.red,
            title: 'РҐР°С‚oР»РёРє',
            msg: 'Р®РєР»aР± Р±СћР»РјaРґРё: ${snap.error}',
          );
        }
        final items = snap.data ?? const <BreadExtraProduct>[];
        if (items.isEmpty) {
          return _empty(
            icon: Icons.local_drink_outlined,
            color: Colors.grey,
            title: 'ТљСћС€РёРјС‡a РјР°ТіСЃСѓР»oС‚ Р№Рѕq',
            msg: 'Р®Т›oСЂРё СћРЅРіРґaРіРё "+ РЇРЅРіРё РјaТіСЃСѓР»oС‚" С‚СѓРіРјaСЃРёРЅРё Р±oСЃРёРЅРі.',
          );
        }
        return LayoutBuilder(builder: (lctx, constraints) {
          final pad = constraints.maxWidth > 800 ? 24.0 : 12.0;
          final cols = (constraints.maxWidth / 380).floor().clamp(1, 3);
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 240,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _ExtraCard(item: items[i]),
          );
        });
      },
    );
  }
}

class _ExtraCard extends StatelessWidget {
  const _ExtraCard({required this.item});
  final BreadExtraProduct item;

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('РЋС‡РёСЂРёС€?'),
        content: Text('"${item.name}" РјaТіСЃСѓР»oС‚РёРЅРё СћС‡РёСЂРёС€РЅРё С…oТіР»aР№cРёР·РјРё?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Р‘РµРєoСЂ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('РЋС‡РёСЂРёС€', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await context.read<BreadRepository>().deleteExtra(item.firestoreId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.button,
            content: Text('рџ—‘ "${item.name}" СћС‡РёСЂРёР»РґРё')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    }
  }

  Future<void> _resetSold(BuildContext context) async {
    try {
      await context.read<BreadRepository>().resetExtraSold(item.firestoreId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: Colors.blue,
            content: Text('рџ”„ "${item.name}" СЃoС‚РёР»РіaРЅ = 0')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(item.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (item.tieToYopishBread)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('С‘РїРёС€',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.teal.shade800,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            if (item.bonusEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                    'рџЋЃ ${item.bonusThreshold}+в†’${item.bonusQty}Г—${item.bonusPercent}%',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('${item.price} СЃСћРј',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(width: 8),
            Text('/ ${item.unitRu}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 10),
          _stockBar(),
          const Spacer(),
          Row(children: [
            IconButton(
              onPressed: () => _resetSold(context),
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'РЎoС‚РёР»РіaРЅ = 0',
              color: Colors.blue.shade600,
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openExtraEditor(context, item),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Tahrir'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary),
            ),
            IconButton(
              onPressed: () => _delete(context),
              icon: Icon(Icons.delete_outline,
                  size: 18, color: Colors.red.shade400),
              tooltip: 'РЋС‡РёСЂРёС€',
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _stockBar() {
    if (item.totalStock <= 0) {
      return Text('Р›РёРјРёС‚СЃРёР·',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500));
    }
    final ratio = (item.soldToday / item.totalStock).clamp(0.0, 1.0);
    final color = ratio > 0.85
        ? Colors.red
        : ratio > 0.6
            ? Colors.orange
            : Colors.green;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('${item.soldToday} / ${item.totalStock} ${item.unitRu}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        const Spacer(),
        Text('ТљoР»РґРё: ${item.remaining}',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 4,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// EDITORS (Modal Dialogs)
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

Future<void> _openBreadEditor(
    BuildContext context, BreadProduct? existing) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _BreadEditorDialog(existing: existing),
  );
}

Future<void> _openExtraEditor(
    BuildContext context, BreadExtraProduct? existing) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _ExtraEditorDialog(existing: existing),
  );
}

Future<void> _openFoodEditor(
    BuildContext context, FoodProduct? existing) async {
  if (existing != null) {
    await showDialog<void>(
      context: context,
      builder: (_) => _FoodProductEditorDialog(
        product: existing,
        docId: 'food_${existing.id}',
      ),
    );
    return;
  }

  final snap = await FirebaseFirestore.instance
      .collection('food_catalog')
      .orderBy('id', descending: true)
      .limit(1)
      .get();
  var newId = 1;
  if (snap.docs.isNotEmpty) {
    final data = snap.docs.first.data();
    newId = ((data['id'] as num?)?.toInt() ?? 0) + 1;
  }
  final product = FoodProduct(
    id: newId,
    name: '',
    emoji: 'рџЌЅ',
    price: 0,
    unit: 'РєРі',
    minQty: 0.5,
    step: 0.5,
    category: '',
    desc: '',
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _FoodProductEditorDialog(
      product: product,
      docId: 'food_$newId',
    ),
  );
}

class _BreadEditorDialog extends StatefulWidget {
  const _BreadEditorDialog({this.existing});
  final BreadProduct? existing;

  @override
  State<_BreadEditorDialog> createState() => _BreadEditorDialogState();
}

class _BreadEditorDialogState extends State<_BreadEditorDialog> {
  /// Р’РµР±РґР° `TextField`РіР° Р¶СѓРґР° СѓР·СѓРЅ `data:imageвЂ¦base64` С‚СѓС€СЃР° layout/СЂРµРЅРґРµСЂ СЃРёРЅР°Р± Т›РѕР»Р°РґРё
  /// (РґРёР°Р»РѕРі В«Р±СћС€В» РєСѓР»СЂР°РЅРі Р±Р»РѕРє СЃРёС„Р°С‚РёРґР° РєСћСЂРёРЅР°РґРё).
  static const int _maxImageUrlCharsInTextField = 8000;

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _emoji;
  late final TextEditingController _imageUrl;
  late final TextEditingController _totalStock;
  late final TextEditingController _desc;
  late final TextEditingController _category;
  late final TextEditingController _unit;
  late final TextEditingController _flourG;
  late final TextEditingController _milkMl;
  String _type = 'tayyor'; // 'tayyor' | 'yopish' | 'toy'
  bool _busy = false;
  bool _pickImageInProgress = false;
  String? _storageDocId;

  /// `imageUrl` Р¶СѓРґР° СѓР·СѓРЅ Р±СћР»СЃР° TextField СћСЂРЅРёРґР° СЃР°Т›Р»Р°РЅР°РґРё (Firestore/СЌСЃРєРё base64).
  String? _stashedOversizedImageUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storageDocId ??= () {
      final fid = widget.existing?.firestoreId?.trim();
      if (fid != null && fid.isNotEmpty) return fid;
      return context.read<BreadRepository>().allocateProductDocId();
    }();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: (e?.price ?? 0).toString());
    _emoji = TextEditingController(text: e?.emoji ?? 'рџ«“');
    final initialImg = e?.imageUrl ?? '';
    if (initialImg.length > _maxImageUrlCharsInTextField) {
      _stashedOversizedImageUrl = initialImg;
      _imageUrl = TextEditingController();
    } else {
      _imageUrl = TextEditingController(text: initialImg);
    }
    _totalStock = TextEditingController(text: (e?.totalStock ?? 0).toString());
    _desc = TextEditingController(text: e?.desc ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _unit = TextEditingController(
        text:
            (e?.unit ?? 'РґРѕРЅР°').trim().isEmpty ? 'РґРѕРЅР°' : (e?.unit ?? 'РґРѕРЅР°'));
    _flourG =
        TextEditingController(text: e?.flourG != null ? '${e!.flourG}' : '');
    _milkMl =
        TextEditingController(text: e?.milkMl != null ? '${e!.milkMl}' : '');
    final t = e?.type ?? 'С‚Р°Р№С‘СЂ';
    if (t == 'С‘РїРёС€') {
      _type = 'yopish';
    } else if (t == 'С‚РѕР№') {
      _type = 'toy';
    } else {
      _type = 'tayyor';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _emoji.dispose();
    _imageUrl.dispose();
    _totalStock.dispose();
    _desc.dispose();
    _category.dispose();
    _unit.dispose();
    _flourG.dispose();
    _milkMl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_pickImageInProgress) return;

    final docId = _storageDocId;
    if (docId == null || docId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
              'РС‡РєРё ID С‚РѕРїРёР»РјР°РґРё вЂ” РґРёР°Р»РѕРіРЅРё С‘РїРёР±, В«РЇРЅРіРё РЅРѕРЅВ»РЅРё Т›Р°Р№С‚Р° РѕС‡РёРЅРі.'),
        ),
      );
      return;
    }

    setState(() => _pickImageInProgress = true);
    try {
      final res = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          )
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => throw TimeoutException('Р¤Р°Р№Р» С‚Р°РЅР»Р°С€ (3 РґР°Т›)'),
          );

      if (res == null || res.files.isEmpty) return;

      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
                'Р¤Р°Р№Р» СћТ›РёР»РјР°РґРё вЂ” РєР°С‚С‚Р° СЂР°СЃРј С‘РєРё Р±СЂР°СѓР·РµСЂ С‡РµРіР°СЂР°СЃРё. РљРёС‡РёРєСЂРѕТ› JPG С‚Р°РЅР»Р°РЅРі.'),
          ),
        );
        return;
      }

      /// Firebase Storage (Firestore ТіСѓР¶Р¶Р°С‚Рё РµРЅРіРёР» вЂ” С„Р°Т›Р°С‚ HTTPS URL).
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
                'Р Р°СЃРј 2 MB РґР°РЅ РєРёС‡РёРє Р±СћР»СЃРёРЅ. РЎРёС„Р°С‚РЅРё РїР°СЃР°Р№С‚РёСЂРёР± Т›Р°Р№С‚Р° С‚Р°РЅР»Р°РЅРі.'),
          ),
        );
        return;
      }

      final name = f.name.toLowerCase();
      final String mime;
      if (name.endsWith('.png')) {
        mime = 'image/png';
      } else if (name.endsWith('.webp')) {
        mime = 'image/webp';
      } else {
        mime = 'image/jpeg';
      }

      final downloadUrl = await BreadImageStorage().uploadBreadProductImage(
        docId: docId,
        bytes: bytes,
        contentType: mime,
      );

      if (!mounted) return;
      _stashedOversizedImageUrl = null;
      _imageUrl.text = downloadUrl;
      setState(() {});

      final existingId = widget.existing?.firestoreId?.trim();
      if (existingId != null && existingId.isNotEmpty) {
        try {
          await context.read<BreadRepository>().mergeProductFields(
            existingId,
            {'imageUrl': downloadUrl},
          ).timeout(const Duration(seconds: 60));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.button,
                content:
                    Text('Р Р°СЃРј СЃР°Т›Р»Р°РЅРґРё вЂ” С„РѕР№РґР°Р»Р°РЅСѓРІС‡Рё РёР»РѕРІР°СЃРёРґР° РєСћСЂРёРЅР°РґРё'),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.orange,
                content: Text('Firestore С‘Р·РёР»РјР°РґРё вЂ” В«РЎР°Т›Р»Р°С€В»РЅРё Р±РѕСЃРёРЅРі: $e'),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.blueGrey,
            content: Text(
              'Р Р°СЃРј С‚Р°Р№С‘СЂ. РљР°С‚Р°Р»РѕРіРіР° С‘Р·РёС€ СѓС‡СѓРЅ В«РЎР°Т›Р»Р°С€В»РЅРё Р±РѕСЃРёРЅРі.',
            ),
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Р’Р°Т›С‚ С‚СѓРіР°РґРё: $e'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Р Р°СЃРј С‚Р°РЅР»Р°С€: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickImageInProgress = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.red, content: Text('РќoРј Р±СћС€ Р±СћР»Р° РѕР»РјaР№РґРё')),
      );
      return;
    }
    final img = () {
      final t = _imageUrl.text.trim();
      if (t.isNotEmpty) return t;
      return _stashedOversizedImageUrl?.trim() ?? '';
    }();
    if (isDataImageUrl(img) && img.length > 950000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
              'ТљСћР»РґР° РєРёСЂРёС‚РёР»РіР°РЅ base64 СЂР°СЃРј Р¶СѓРґР° РєР°С‚С‚Р° вЂ” В«Р Р°СЃРј С‚Р°РЅР»Р°С€В» РѕСЂТ›Р°Р»Рё СЋРєР»Р°РЅРі С‘РєРё URL Т›РёСЃТ›Р°СЂС‚РёСЂРёРЅРі.'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final flour = int.tryParse(_flourG.text.trim());
      final milk = int.tryParse(_milkMl.text.trim());
      await context.read<BreadRepository>().upsertProduct(
            id: widget.existing?.firestoreId ?? _storageDocId,
            name: _name.text.trim(),
            type: _type,
            price: int.tryParse(_price.text) ?? 0,
            emoji: _emoji.text.trim().isEmpty ? 'рџ«“' : _emoji.text.trim(),
            imageUrl: img,
            description: _desc.text.trim(),
            category: _category.text.trim(),
            unit: _unit.text.trim().isEmpty ? 'РґРѕРЅР°' : _unit.text.trim(),
            flourG: (_type == 'yopish' || _type == 'toy') ? flour : null,
            milkMl: (_type == 'yopish' || _type == 'toy') ? milk : null,
            totalStock: int.tryParse(_totalStock.text) ?? 0,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.button,
            content: Text(
                '${widget.existing == null ? "РЇРЅРіРё РЅoРЅ" : "РќoРЅ СЏРЅРіРёР»aРЅРґРё"}: ${_name.text}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFlourMilk = _type == 'yopish' || _type == 'toy';
    final dialogW = (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 460.0);
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(widget.existing == null ? 'рџ«“ РЇРЅРіРё РЅoРЅ' : 'рџ«“ РќoРЅРЅРё tahrir'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_stashedOversizedImageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 20, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Р Р°СЃРј СЌСЃРєРё СѓСЃСѓР»РґР° (Firestore РёС‡РёРґР°) Р¶СѓРґР° СѓР·СѓРЅ СЃР°Т›Р»Р°РЅРіР°РЅ вЂ” '
                                'РІРµР± С„РѕСЂРјР° С‡РёТ›РёС€Рё СѓС‡СѓРЅ URL РјР°Р№РґРѕРЅРё Р±СћС€. В«Р Р°СЃРј С‚Р°РЅР»Р°С€В» Р±РёР»Р°РЅ '
                                'Storage РіР° СЋРєР»Р°Р± СЏРЅРіРёР»Р°РЅРі С‘РєРё В«РЎР°Т›Р»Р°С€В» Р±РёР»Р°РЅ РЅРѕРј/РЅР°СЂС…РЅРё СЃР°Т›Р»Р°РЅРі.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _field(_name, 'РќoРј', icon: Icons.short_text, maxLen: 50),
                const SizedBox(height: 10),
                _typeSelector(),
                const SizedBox(height: 10),
                _field(_price, 'РќaСЂС… (СЃСћРј)',
                    icon: Icons.attach_money,
                    keyboard: TextInputType.number,
                    digits: true,
                    maxLen: 7),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _field(_emoji, 'Emoji',
                        icon: Icons.emoji_food_beverage, maxLen: 4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(_totalStock, 'Р–aРјРё Р·aС…РёСЂa',
                        icon: Icons.inventory_2,
                        keyboard: TextInputType.number,
                        digits: true,
                        maxLen: 5,
                        helper: '0 = Р»РёРјРёС‚СЃРёР·'),
                  ),
                ]),
                const SizedBox(height: 10),
                _field(_desc, 'РўР°РІСЃРёС„',
                    icon: Icons.notes, maxLen: 500, maxLines: 3),
                const SizedBox(height: 10),
                _field(_category, 'РљР°С‚РµРіРѕСЂРёСЏ (РјР°СЃ. РљРёС‡РёРє / РЋСЂС‚Р°С‡Р°)',
                    icon: Icons.category, maxLen: 40),
                const SizedBox(height: 10),
                _field(_unit, 'РЋР»С‡РѕРІ Р±РёСЂР»РёРіРё',
                    icon: Icons.straighten,
                    maxLen: 20,
                    helper: 'РґРѕРЅР°, РєРі, Р» вЂ¦'),
                if (showFlourMilk) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _field(_flourG, 'РЈРЅ (Рі) вЂ” РёС…С‚РёС‘СЂРёР№',
                          icon: Icons.grass,
                          keyboard: TextInputType.number,
                          digits: true,
                          maxLen: 5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(_milkMl, 'РЎСѓС‚ (РјР») вЂ” РёС…С‚РёС‘СЂРёР№',
                          icon: Icons.local_drink,
                          keyboard: TextInputType.number,
                          digits: true,
                          maxLen: 5),
                    ),
                  ]),
                ],
                const SizedBox(height: 10),
                Text('Р Р°СЃРј',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                _breadImagePreview(),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_busy || _pickImageInProgress) ? null : _pickImage,
                    icon: _pickImageInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.photo_library_outlined, size: 20),
                    label: Text(
                      _pickImageInProgress
                          ? 'Р®РєР»Р°РЅРјРѕТ›РґР°...'
                          : 'Р Р°СЃРј С‚Р°РЅР»Р°С€ (Storage, в‰¤2 MB)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'РўР°РЅР»Р°РЅРіР°РЅ С„Р°Р№Р» Firebase Storage РіР° СЋРєР»Р°РЅР°РґРё; HTTPS URL С‘РєРё Т›СћР»РґР° base64 ТіР°Рј РјСѓРјРєРёРЅ.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 6),
                _field(_imageUrl, 'Р Р°СЃРј URL (Р°РІС‚Рѕ С‚СћР»РґРёСЂРёР»Р°РґРё С‘РєРё Т›СћР»РґР°)',
                    icon: Icons.link, maxLen: 4096, maxLines: 2),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Р‘РµРєoСЂ')),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('РЎaТ›Р»aС€'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _breadImagePreview() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _imageUrl,
      builder: (context, value, _) {
        final rawField = value.text.trim();
        final raw = rawField.isNotEmpty
            ? rawField
            : (_stashedOversizedImageUrl?.trim() ?? '');
        if (raw.isNotEmpty && isDataImageUrl(raw) && raw.length > 140000) {
          return Container(
            height: 100,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Text(
                'Preview С‡РµРєР»Р°РЅРіР°РЅ (Р¶СѓРґР° СѓР·СѓРЅ base64).\n'
                'В«Р Р°СЃРј С‚Р°РЅР»Р°С€В» вЂ” Storage URL С‚Р°РІСЃРёСЏ.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          );
        }
        final mem = decodeDataUrlImageBytes(raw);
        if (mem != null && mem.isNotEmpty) {
          return Container(
            constraints: const BoxConstraints(maxHeight: 160),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.memory(
                mem,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    _emoji.text.trim().isEmpty ? 'рџ«“' : _emoji.text.trim(),
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
          );
        }
        if (raw.isNotEmpty && isHttpImageUrl(raw)) {
          return Container(
            constraints: const BoxConstraints(maxHeight: 160),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(
                raw,
                height: 140,
                width: double.infinity,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 140,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    _emoji.text.trim().isEmpty ? 'рџ«“' : _emoji.text.trim(),
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
          );
        }
        return Container(
          height: 100,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Center(
            child: Text(
              _emoji.text.trim().isEmpty ? 'рџ«“' : _emoji.text.trim(),
              style: const TextStyle(fontSize: 56),
            ),
          ),
        );
      },
    );
  }

  Widget _typeSelector() {
    final options = [
      ('tayyor', 'РўaР№С‘СЂ', Icons.shopping_basket),
      ('yopish', 'РЃРїРёС€ (РҐРђ)', Icons.local_fire_department),
      ('toy', 'РўСћР№', Icons.celebration),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('РўСѓСЂРё', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, children: [
        for (final o in options)
          ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(o.$3, size: 14),
              const SizedBox(width: 4),
              Text(o.$2),
            ]),
            selected: _type == o.$1,
            onSelected: (_) => setState(() => _type = o.$1),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
          ),
      ]),
    ]);
  }
}

class _ExtraEditorDialog extends StatefulWidget {
  const _ExtraEditorDialog({this.existing});
  final BreadExtraProduct? existing;

  @override
  State<_ExtraEditorDialog> createState() => _ExtraEditorDialogState();
}

class _ExtraEditorDialogState extends State<_ExtraEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _totalStock;
  late final TextEditingController _bonusThreshold;
  late final TextEditingController _bonusQty;
  late final TextEditingController _bonusPercent;
  late final TextEditingController _emoji;
  late final TextEditingController _caption;
  late final TextEditingController _imageUrl;
  String _unit = 'dona'; // 'dona' | 'kg' | 'l'
  bool _bonusEnabled = false;
  bool _tieToYopishBread = false;
  bool _busy = false;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: (e?.price ?? 0).toString());
    _totalStock = TextEditingController(text: (e?.totalStock ?? 0).toString());
    _bonusThreshold =
        TextEditingController(text: (e?.bonusThreshold ?? 0).toString());
    _bonusQty = TextEditingController(text: (e?.bonusQty ?? 0).toString());
    _bonusPercent =
        TextEditingController(text: (e?.bonusPercent ?? 0).toString());
    _emoji = TextEditingController(text: e?.emoji ?? '');
    _caption = TextEditingController(text: e?.caption ?? '');
    _imageUrl = TextEditingController(text: e?.imageUrl ?? '');
    _unit = e?.unitCode ?? 'dona';
    _bonusEnabled = e?.bonusEnabled ?? false;
    _tieToYopishBread = e?.tieToYopishBread ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _totalStock.dispose();
    _bonusThreshold.dispose();
    _bonusQty.dispose();
    _bonusPercent.dispose();
    _emoji.dispose();
    _caption.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  String _mimeForName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;

    final repo = context.read<BreadRepository>();
    final docId = widget.existing?.firestoreId;
    if (docId == null || docId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('РђРІРІР°Р» РјР°ТіСЃСѓР»РѕС‚РЅРё СЃР°Т›Р»Р°РЅРі, РєРµР№РёРЅ СЂР°СЃРј СЋРєР»Р°РЅРі.'),
        ),
      );
      return;
    }

    setState(() => _uploadingImage = true);
    try {
      final res = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          )
          .timeout(const Duration(minutes: 3));
      if (res == null || res.files.isEmpty) return;

      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Р¤Р°Р№Р» СћТ›РёР»РјР°РґРё вЂ” РєРёС‡РёРєСЂРѕТ› JPG/PNG С‚Р°РЅР»Р°РЅРі.'),
          ),
        );
        return;
      }
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Р Р°СЃРј 2 MB РґР°РЅ РєРёС‡РёРє Р±СћР»СЃРёРЅ.'),
          ),
        );
        return;
      }

      final url = await BreadImageStorage().uploadExtraImage(
        docId: docId,
        bytes: bytes,
        contentType: _mimeForName(f.name),
      );
      _imageUrl.text = url;
      await repo.upsertExtra(
            id: docId,
            name: _name.text.trim(),
            price: int.tryParse(_price.text) ?? 0,
            unit: _unit,
            totalStock: int.tryParse(_totalStock.text) ?? 0,
            bonusEnabled: _bonusEnabled,
            bonusThreshold: int.tryParse(_bonusThreshold.text) ?? 0,
            bonusQty: int.tryParse(_bonusQty.text) ?? 0,
            bonusPercent: int.tryParse(_bonusPercent.text) ?? 0,
            emoji: _emoji.text.trim(),
            caption: _caption.text.trim(),
            imageUrl: url,
            tieToYopishBread: _tieToYopishBread,
          );

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('Р Р°СЃРј СЋРєР»Р°РЅРґРё'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Р Р°СЃРј: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.red, content: Text('РќoРј Р±СћС€ Р±СћР»Р° РѕР»РјaР№РґРё')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<BreadRepository>().upsertExtra(
            id: widget.existing?.firestoreId,
            name: _name.text.trim(),
            price: int.tryParse(_price.text) ?? 0,
            unit: _unit,
            totalStock: int.tryParse(_totalStock.text) ?? 0,
            bonusEnabled: _bonusEnabled,
            bonusThreshold: int.tryParse(_bonusThreshold.text) ?? 0,
            bonusQty: int.tryParse(_bonusQty.text) ?? 0,
            bonusPercent: int.tryParse(_bonusPercent.text) ?? 0,
            emoji: _emoji.text.trim(),
            caption: _caption.text.trim(),
            imageUrl: _imageUrl.text.trim(),
            tieToYopishBread: _tieToYopishBread,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.button,
            content: Text(
                '${widget.existing == null ? "РЇРЅРіРё РјaТіСЃСѓР»oС‚" : "РЇРЅРіРёР»aРЅРґРё"}: ${_name.text}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('РҐР°С‚oР»РёРє: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'рџЊї РЇРЅРіРё Т›СћС€РёРјС‡a' : 'рџЊї ТљСћС€РёРјС‡aРЅРё tahrir'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 320),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _foodImagePreview(
              _imageUrl,
              _emoji.text.trim().isEmpty ? 'рџЊї' : _emoji.text.trim(),
              height: 150,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_busy || _uploadingImage) ? null : _pickAndUploadImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_uploadingImage ? 'Р®РєР»Р°РЅРјРѕТ›РґР°...' : 'Р Р°СЃРј С‚Р°РЅР»Р°С€'),
              ),
            ),
            const SizedBox(height: 10),
            _field(_name, 'РќoРј', icon: Icons.short_text, maxLen: 50),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _field(_emoji, 'Emoji (РёС…С‚РёС‘СЂРёР№)',
                    icon: Icons.emoji_emotions_outlined, maxLen: 8),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(_caption, 'РР·РѕТі (РјР°СЃР°Р»Р°РЅ 2Рі/РЅРѕРЅ)',
                    icon: Icons.notes, maxLen: 80),
              ),
            ]),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('РЃРїРёС€ РЅРѕРЅРё Р±РёР»Р°РЅ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Р¤Р°Т›Р°С‚ СЃР°РІР°С‚РґР° С‘РїРёС€ РЅРѕРЅРё Р±СћР»СЃР° РєСћСЂРёРЅР°РґРё; РјР°РєСЃ. = С‘РїРёС€ РЅРѕРЅРё СЃРѕРЅРё',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              value: _tieToYopishBread,
              onChanged: (v) => setState(() => _tieToYopishBread = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                flex: 2,
                child: _field(_price, 'РќaСЂС… (СЃСћРј)',
                    icon: Icons.attach_money,
                    keyboard: TextInputType.number,
                    digits: true,
                    maxLen: 7),
              ),
              const SizedBox(width: 10),
              Expanded(child: _unitSelector()),
            ]),
            const SizedBox(height: 10),
            _field(_totalStock, 'Р–aРјРё Р·aС…РёСЂa',
                icon: Icons.inventory_2,
                keyboard: TextInputType.number,
                digits: true,
                maxLen: 5,
                helper: '0 = Р»РёРјРёС‚СЃРёР·'),
            const SizedBox(height: 10),
            _field(_imageUrl, 'Р Р°СЃРј URL',
                icon: Icons.link, maxLen: 4096, maxLines: 2),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('рџЋЃ Р§РµРіРёСЂРјa Р±РѕРЅСѓСЃРё',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'РњaСЃaР»aРЅ: 3 С‚Р° СЃoС‚РёР± oР»РіaРЅРіР° 1 С‚aСЃРё 50% Р°СЂР·oРЅРіa',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                      value: _bonusEnabled,
                      onChanged: (v) => setState(() => _bonusEnabled = v),
                    ),
                    if (_bonusEnabled) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: _field(_bonusThreshold, 'Р§РµРіaСЂa',
                              icon: Icons.filter_alt,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'ТљaРЅС‡a С‚aРґaРЅ'),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _field(_bonusQty, 'РњРёРє-СЂ',
                              icon: Icons.numbers,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'РќРµС‡a С‚aСЃРё'),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _field(_bonusPercent, '%',
                              icon: Icons.percent,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'AСЂР·oРЅР»РёРє'),
                        ),
                      ]),
                    ],
                  ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Р‘РµРєoСЂ')),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('РЎaТ›Р»aС€'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _unitSelector() {
    return DropdownButtonFormField<String>(
      initialValue: _unit,
      decoration: InputDecoration(
        labelText: 'Р‘РёСЂР»РёРє',
        prefixIcon: const Icon(Icons.straighten, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'dona', child: Text('рџ”ў Р”oРЅa')),
        DropdownMenuItem(value: 'kg', child: Text('вљ–пёЏ РљРі')),
        DropdownMenuItem(value: 'l', child: Text('рџ§ґ Р›РёС‚СЂ')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _unit = v);
      },
    );
  }
}

// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ
// SHARED
// в•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђв•ђ

Widget _field(
  TextEditingController ctrl,
  String label, {
  IconData? icon,
  TextInputType keyboard = TextInputType.text,
  bool digits = false,
  int maxLen = 100,
  String? helper,
  int maxLines = 1,
}) {
  return TextField(
    controller: ctrl,
    keyboardType: keyboard,
    maxLength: maxLen,
    maxLines: maxLines,
    inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon != null ? Icon(icon, size: 18) : null,
      counterText: '',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    ),
  );
}

Widget _empty({
  required IconData icon,
  required Color color,
  required String title,
  required String msg,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: color),
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(msg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      ]),
    ),
  );
}
