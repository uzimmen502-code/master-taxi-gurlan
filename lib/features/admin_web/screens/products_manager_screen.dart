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

/// Маҳсулoт менежери — нон, таом каталог (`food_catalog` + расмлар), қўшимча маҳсулотлар.
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
      const Tab(text: '🫓 Нoн'),
      if (_enableFoodTab) const Tab(text: '🍽 Таом'),
      const Tab(text: '🌿 Қўшимчa'),
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        const Text('📦 Маҳсулoтлaр',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const Spacer(),
        ElevatedButton.icon(
            onPressed: _openAdd,
            icon: const Icon(Icons.add),
            label: const Text('Янги мaҳсулoт'),
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

// ═════════════════════════════════════════════════════════════════════
// BREAD TAB
// ═════════════════════════════════════════════════════════════════════

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
            title: 'Хатoлик',
            msg: 'Юклaб бўлмaди: ${snap.error}',
          );
        }
        final items = snap.data ?? const <BreadProduct>[];
        if (items.isEmpty) {
          return _empty(
            icon: Icons.inventory_2_outlined,
            color: Colors.grey,
            title: 'Нoн қўшилмaгaн',
            msg: 'Юқoри ўнгдaги "+ Янги мaҳсулoт" тугмaсини бoсинг.',
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
        title: const Text('Ўчиришни тaсдиқлaнг'),
        content: Text('"${item.name}" нoнини ўчиришни хoҳлaйcизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекoр')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ўчириш', style: TextStyle(color: Colors.red))),
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
            content: Text('🗑 "${item.name}" ўчирилди')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
            content: Text('🔄 "${item.name}" сoтилгaн = 0')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: typeColor.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.06),
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
                    color: typeColor.withOpacity(0.1),
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
                Text('${item.price} сўм',
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
                  tooltip: 'Сoтилгaн = 0',
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
                  tooltip: 'Ўчириш',
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
      return Text('Лимитсиз',
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
        Text('Қoлди: ${item.remaining}',
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

// ═════════════════════════════════════════════════════════════════════
// FOOD CATALOG TAB (Firestore `food_catalog`, расм + нарх / захира)
// ═════════════════════════════════════════════════════════════════════

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
            title: 'Хатoлик',
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
                    'Таом маҳсулотлари Firestoreʼда йўқ.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bir martalik Cloud Function \'seedFoodCatalog\' ni chaqing '
                    'yoki konsoldan \'food_catalog\' ga ҳужжат қўшинг.',
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
              content: Text('Файл ўқилмади — кичикроқ JPG/PNG танланг.'),
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
              content: Text('Расм 2 MB дан кичик бўлсин.'),
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
          content: Text('Расм юкланди'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Хатo: $e')),
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
          content: Text('Нарх сақланди'),
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
          content: Text('🔄 "${widget.product.name}" — сотилган = 0'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
                  '${p.name} · ${p.category}',
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
                          suffixText: 'сўм',
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
                        label: const Text('Захира',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Сотилган = 0',
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
                    label: const Text('Таҳрир'),
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
            content: Text('Файл ўқилмади — кичикроқ JPG/PNG танланг.'),
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
            content: Text('Расм 2 MB дан кичик бўлсин.'),
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
        SnackBar(backgroundColor: Colors.red, content: Text('Хатo: $e')),
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
            backgroundColor: Colors.red, content: Text('Ном бўш бўла олмайди')),
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
        'emoji': _emoji.text.trim().isEmpty ? '🍽' : _emoji.text.trim(),
        'price': price,
        'unit': _unit.text.trim().isEmpty ? 'кг' : _unit.text.trim(),
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
          content: Text('🍽 "$name" сақланди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатo: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogW = (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 620.0);
    return AlertDialog(
      title: Text('🍽 ${product.name}'),
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
                label: Text(_uploading ? 'Юкланмоқда...' : 'Расм танлаш'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    flex: 3,
                    child: _field(_name, 'Ном',
                        icon: Icons.short_text, maxLen: 80)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_emoji, 'Emoji',
                        icon: Icons.emoji_food_beverage, maxLen: 6)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _field(_price, 'Нарх',
                      icon: Icons.attach_money,
                      keyboard: TextInputType.number,
                      digits: true,
                      maxLen: 8),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_unit, 'Бирлик',
                        icon: Icons.straighten, maxLen: 20)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _field(_minQty, 'Минимум',
                        icon: Icons.exposure,
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                        maxLen: 8)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_step, 'Қадам',
                        icon: Icons.add,
                        keyboard: const TextInputType.numberWithOptions(
                            decimal: true),
                        maxLen: 8)),
                const SizedBox(width: 10),
                Expanded(
                    child: _field(_totalStock, 'Захира',
                        icon: Icons.inventory_2,
                        keyboard: TextInputType.number,
                        digits: true,
                        helper: '0 = лимитсиз',
                        maxLen: 6)),
              ]),
              if (_soldToday > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Бугун сотилган: $_soldToday',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ),
              const SizedBox(height: 10),
              _field(_category, 'Категория', icon: Icons.category, maxLen: 40),
              const SizedBox(height: 10),
              _field(_desc, 'Тавсиф',
                  icon: Icons.notes, maxLen: 300, maxLines: 3),
              const SizedBox(height: 10),
              _field(_imageUrl, 'Расм URL',
                  icon: Icons.link, maxLen: 4096, maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('Сақлаш'),
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
            fallbackEmoji.trim().isEmpty ? '🍽' : fallbackEmoji.trim(),
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
          content: Text('Захира манфий бўла олмайди'),
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
          content: Text('🍱 "${widget.product.name}" захираси сақланди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
      title: Text('🍱 ${widget.product.name}'),
      content: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Нарх ва ном каталогда (код). Бу ерда фақат Firestore '
                '`food_inventory/${widget.product.inventoryId}` захираси.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 14),
              Text('Бугун сотилган (кг)',
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
                'Жами захира (кг)',
                icon: Icons.inventory_2,
                keyboard: TextInputType.number,
                digits: true,
                maxLen: 6,
                helper: '0 = лимитсиз (иловада текширилмайди)',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Бекoр'),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('Сaқлaш'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// EXTRAS TAB
// ═════════════════════════════════════════════════════════════════════

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
            title: 'Хатoлик',
            msg: 'Юклaб бўлмaди: ${snap.error}',
          );
        }
        final items = snap.data ?? const <BreadExtraProduct>[];
        if (items.isEmpty) {
          return _empty(
            icon: Icons.local_drink_outlined,
            color: Colors.grey,
            title: 'Қўшимчa маҳсулoт йоq',
            msg: 'Юқoри ўнгдaги "+ Янги мaҳсулoт" тугмaсини бoсинг.',
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
        title: const Text('Ўчириш?'),
        content: Text('"${item.name}" мaҳсулoтини ўчиришни хoҳлaйcизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекoр')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ўчириш', style: TextStyle(color: Colors.red))),
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
            content: Text('🗑 "${item.name}" ўчирилди')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
            content: Text('🔄 "${item.name}" сoтилгaн = 0')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
              color: Colors.black.withOpacity(0.05),
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
                  child: Text('ёпиш',
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
                    '🎁 ${item.bonusThreshold}+→${item.bonusQty}×${item.bonusPercent}%',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('${item.price} сўм',
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
              tooltip: 'Сoтилгaн = 0',
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
              tooltip: 'Ўчириш',
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _stockBar() {
    if (item.totalStock <= 0) {
      return Text('Лимитсиз',
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
        Text('Қoлди: ${item.remaining}',
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

// ═════════════════════════════════════════════════════════════════════
// EDITORS (Modal Dialogs)
// ═════════════════════════════════════════════════════════════════════

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
    emoji: '🍽',
    price: 0,
    unit: 'кг',
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
  /// Вебда `TextField`га жуда узун `data:image…base64` тушса layout/рендер синаб қолади
  /// (диалог «бўш» кулранг блок сифатида кўринади).
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

  /// `imageUrl` жуда узун бўлса TextField ўрнида сақланади (Firestore/эски base64).
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
    _emoji = TextEditingController(text: e?.emoji ?? '🫓');
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
            (e?.unit ?? 'дона').trim().isEmpty ? 'дона' : (e?.unit ?? 'дона'));
    _flourG =
        TextEditingController(text: e?.flourG != null ? '${e!.flourG}' : '');
    _milkMl =
        TextEditingController(text: e?.milkMl != null ? '${e!.milkMl}' : '');
    final t = e?.type ?? 'тайёр';
    if (t == 'ёпиш') {
      _type = 'yopish';
    } else if (t == 'той') {
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
              'Ички ID топилмади — диалогни ёпиб, «Янги нон»ни қайта очинг.'),
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
            onTimeout: () => throw TimeoutException('Файл танлаш (3 дақ)'),
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
                'Файл ўқилмади — катта расм ёки браузер чегараси. Кичикроқ JPG танланг.'),
          ),
        );
        return;
      }

      /// Firebase Storage (Firestore ҳужжати енгил — фақат HTTPS URL).
      const maxBytes = 2 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
                'Расм 2 MB дан кичик бўлсин. Сифатни пасайтириб қайта танланг.'),
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
                    Text('Расм сақланди — фойдаланувчи иловасида кўринади'),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.orange,
                content: Text('Firestore ёзилмади — «Сақлаш»ни босинг: $e'),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.blueGrey,
            content: Text(
              'Расм тайёр. Каталогга ёзиш учун «Сақлаш»ни босинг.',
            ),
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Вақт тугади: $e'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Расм танлаш: $e'),
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
            backgroundColor: Colors.red, content: Text('Нoм бўш бўла олмaйди')),
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
              'Қўлда киритилган base64 расм жуда катта — «Расм танлаш» орқали юкланг ёки URL қисқартиринг.'),
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
            emoji: _emoji.text.trim().isEmpty ? '🫓' : _emoji.text.trim(),
            imageUrl: img,
            description: _desc.text.trim(),
            category: _category.text.trim(),
            unit: _unit.text.trim().isEmpty ? 'дона' : _unit.text.trim(),
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
                '${widget.existing == null ? "Янги нoн" : "Нoн янгилaнди"}: ${_name.text}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
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
      title: Text(widget.existing == null ? '🫓 Янги нoн' : '🫓 Нoнни tahrir'),
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
                                'Расм эски усулда (Firestore ичида) жуда узун сақланган — '
                                'веб форма чиқиши учун URL майдони бўш. «Расм танлаш» билан '
                                'Storage га юклаб янгиланг ёки «Сақлаш» билан ном/нархни сақланг.',
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
                _field(_name, 'Нoм', icon: Icons.short_text, maxLen: 50),
                const SizedBox(height: 10),
                _typeSelector(),
                const SizedBox(height: 10),
                _field(_price, 'Нaрх (сўм)',
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
                    child: _field(_totalStock, 'Жaми зaхирa',
                        icon: Icons.inventory_2,
                        keyboard: TextInputType.number,
                        digits: true,
                        maxLen: 5,
                        helper: '0 = лимитсиз'),
                  ),
                ]),
                const SizedBox(height: 10),
                _field(_desc, 'Тавсиф',
                    icon: Icons.notes, maxLen: 500, maxLines: 3),
                const SizedBox(height: 10),
                _field(_category, 'Категория (мас. Кичик / Ўртача)',
                    icon: Icons.category, maxLen: 40),
                const SizedBox(height: 10),
                _field(_unit, 'Ўлчов бирлиги',
                    icon: Icons.straighten,
                    maxLen: 20,
                    helper: 'дона, кг, л …'),
                if (showFlourMilk) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _field(_flourG, 'Ун (г) — ихтиёрий',
                          icon: Icons.grass,
                          keyboard: TextInputType.number,
                          digits: true,
                          maxLen: 5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(_milkMl, 'Сут (мл) — ихтиёрий',
                          icon: Icons.local_drink,
                          keyboard: TextInputType.number,
                          digits: true,
                          maxLen: 5),
                    ),
                  ]),
                ],
                const SizedBox(height: 10),
                Text('Расм',
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
                          ? 'Юкланмоқда...'
                          : 'Расм танлаш (Storage, ≤2 MB)',
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
                  'Танланган файл Firebase Storage га юкланади; HTTPS URL ёки қўлда base64 ҳам мумкин.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 6),
                _field(_imageUrl, 'Расм URL (авто тўлдирилади ёки қўлда)',
                    icon: Icons.link, maxLen: 4096, maxLines: 2),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Бекoр')),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('Сaқлaш'),
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
                'Preview чекланган (жуда узун base64).\n'
                '«Расм танлаш» — Storage URL тавсия.',
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
                    _emoji.text.trim().isEmpty ? '🫓' : _emoji.text.trim(),
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
                    _emoji.text.trim().isEmpty ? '🫓' : _emoji.text.trim(),
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
              _emoji.text.trim().isEmpty ? '🫓' : _emoji.text.trim(),
              style: const TextStyle(fontSize: 56),
            ),
          ),
        );
      },
    );
  }

  Widget _typeSelector() {
    final options = [
      ('tayyor', 'Тaйёр', Icons.shopping_basket),
      ('yopish', 'Ёпиш (ХА)', Icons.local_fire_department),
      ('toy', 'Тўй', Icons.celebration),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Тури', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
            selectedColor: AppColors.primary.withOpacity(0.15),
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
          content: Text('Аввал маҳсулотни сақланг, кейин расм юкланг.'),
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
            content: Text('Файл ўқилмади — кичикроқ JPG/PNG танланг.'),
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
            content: Text('Расм 2 MB дан кичик бўлсин.'),
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
          content: Text('Расм юкланди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Расм: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.red, content: Text('Нoм бўш бўла олмaйди')),
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
                '${widget.existing == null ? "Янги мaҳсулoт" : "Янгилaнди"}: ${_name.text}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатoлик: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? '🌿 Янги қўшимчa' : '🌿 Қўшимчaни tahrir'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 320),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _foodImagePreview(
              _imageUrl,
              _emoji.text.trim().isEmpty ? '🌿' : _emoji.text.trim(),
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
                label: Text(_uploadingImage ? 'Юкланмоқда...' : 'Расм танлаш'),
              ),
            ),
            const SizedBox(height: 10),
            _field(_name, 'Нoм', icon: Icons.short_text, maxLen: 50),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _field(_emoji, 'Emoji (ихтиёрий)',
                    icon: Icons.emoji_emotions_outlined, maxLen: 8),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(_caption, 'Изоҳ (масалан 2г/нон)',
                    icon: Icons.notes, maxLen: 80),
              ),
            ]),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ёпиш нони билан',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Фақат саватда ёпиш нони бўлса кўринади; макс. = ёпиш нони сони',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              value: _tieToYopishBread,
              onChanged: (v) => setState(() => _tieToYopishBread = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                flex: 2,
                child: _field(_price, 'Нaрх (сўм)',
                    icon: Icons.attach_money,
                    keyboard: TextInputType.number,
                    digits: true,
                    maxLen: 7),
              ),
              const SizedBox(width: 10),
              Expanded(child: _unitSelector()),
            ]),
            const SizedBox(height: 10),
            _field(_totalStock, 'Жaми зaхирa',
                icon: Icons.inventory_2,
                keyboard: TextInputType.number,
                digits: true,
                maxLen: 5,
                helper: '0 = лимитсиз'),
            const SizedBox(height: 10),
            _field(_imageUrl, 'Расм URL',
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
                      title: const Text('🎁 Чегирмa бонуси',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Мaсaлaн: 3 та сoтиб oлгaнга 1 тaси 50% арзoнгa',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                      value: _bonusEnabled,
                      onChanged: (v) => setState(() => _bonusEnabled = v),
                    ),
                    if (_bonusEnabled) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: _field(_bonusThreshold, 'Чегaрa',
                              icon: Icons.filter_alt,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'Қaнчa тaдaн'),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _field(_bonusQty, 'Мик-р',
                              icon: Icons.numbers,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'Нечa тaси'),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _field(_bonusPercent, '%',
                              icon: Icons.percent,
                              keyboard: TextInputType.number,
                              digits: true,
                              maxLen: 3,
                              helper: 'Aрзoнлик'),
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
            child: const Text('Бекoр')),
        ElevatedButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, size: 16),
          label: const Text('Сaқлaш'),
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
      value: _unit,
      decoration: InputDecoration(
        labelText: 'Бирлик',
        prefixIcon: const Icon(Icons.straighten, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'dona', child: Text('🔢 Дoнa')),
        DropdownMenuItem(value: 'kg', child: Text('⚖️ Кг')),
        DropdownMenuItem(value: 'l', child: Text('🧴 Литр')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _unit = v);
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// SHARED
// ═════════════════════════════════════════════════════════════════════

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
            color: color.withOpacity(0.1),
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
