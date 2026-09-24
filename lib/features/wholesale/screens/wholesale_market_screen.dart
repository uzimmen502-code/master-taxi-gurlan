import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_sellers_repository.dart';
import '../services/wholesale_video_link.dart';
import '../widgets/wholesale_product_card.dart';
import 'wholesale_product_detail_screen.dart';
import 'wholesale_product_form_screen.dart';

/// Улгуржи/кичик улгуржи бозор — умумий кириш нуқтаси.
/// "Бозор" (ҳамма кўради) + "Мен сотувчиман" (рўйхатдан ўтиш → admin
/// тасдиғи → маҳсулот қўшиш).
class WholesaleMarketScreen extends StatefulWidget {
  const WholesaleMarketScreen({super.key, required this.userPhone});

  /// Жорий фойдаланувчи телефони — бош экрандан узатилади (`HomeController`
  /// фақат Home subtree'ида мавжуд, push қилинган экранда `context.read`
  /// ишламайди — ProviderNotFound, қурилмада бўш экран бўлган).
  final String userPhone;

  @override
  State<WholesaleMarketScreen> createState() => _WholesaleMarketScreenState();
}

class _WholesaleMarketScreenState extends State<WholesaleMarketScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _productsRepo = WholesaleProductsRepository();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Улгуржи бозор'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(text: 'Бозор'),
            Tab(text: 'Сотувчи'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_marketTab(), _SellerAreaTab(phone: widget.userPhone)],
      ),
    );
  }

  Widget _marketTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Маҳсулот, компания номи бўйича қидириш...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<WholesaleProduct>>(
          stream: _query.trim().isEmpty
              ? _productsRepo.getActiveProducts()
              : _productsRepo.searchActiveProducts(_query),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const <WholesaleProduct>[];
            if (items.isEmpty) {
              return const Center(child: Text('Маҳсулот топилмади'));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => WholesaleProductCard(
                product: items[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        WholesaleProductDetailScreen(product: items[i]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// "Мен сотувчиман" — сотувчи ҳолатига қараб: рўйхатдан ўтиш формаси,
/// кутилмоқда/рад этилган ҳолат, ёки ўз маҳсулотлари рўйхати.
class _SellerAreaTab extends StatefulWidget {
  const _SellerAreaTab({required this.phone});

  final String phone;

  @override
  State<_SellerAreaTab> createState() => _SellerAreaTabState();
}

class _SellerAreaTabState extends State<_SellerAreaTab> {
  final _sellersRepo = WholesaleSellersRepository();
  final _companyCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  String _sellerType = '';
  bool _registering = false;

  @override
  void dispose() {
    _companyCtrl.dispose();
    _ownerCtrl.dispose();
    super.dispose();
  }

  String get _phone => widget.phone;

  Future<void> _register() async {
    final company = _companyCtrl.text.trim();
    if (company.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Компания номини киритинг')),
      );
      return;
    }
    if (_sellerType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сотувчи турини танланг')),
      );
      return;
    }
    setState(() => _registering = true);
    try {
      await _sellersRepo.register(
        phone: _phone,
        companyName: company,
        ownerName: _ownerCtrl.text.trim(),
        sellerType: _sellerType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Юборилди — admin тасдиғини кутинг'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    if (phone.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Сотувчи бўлиш учун аввал профилда телефон рақамингизни тасдиқланг.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return StreamBuilder<WholesaleSeller?>(
      stream: _sellersRepo.watchByPhone(phone),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final seller = snap.data;
        if (seller == null) return _registerForm();
        if (seller.isPending) return _statusCard(seller);
        if (seller.isRejected) return _statusCard(seller);
        return _MyProductsView(seller: seller);
      },
    );
  }

  Widget _registerForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Улгуржи сотувчи сифатида рўйхатдан ўтинг',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Ишлаб чиқарувчи, оптовик ёки ЯТТ сифатида маҳсулотларингизни улгуржи/кичик улгуржи савдога қўйишингиз мумкин. Рўйхатдан ўтгач, admin тасдиғидан кейин маҳсулот жойлаштира оласиз.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 20),
        const Text('Сиз кимсиз?',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final t in WholesaleSeller.sellerTypes)
            ChoiceChip(
              label: Text(WholesaleSeller.typeLabel(t)),
              selected: _sellerType == t,
              onSelected: (_) => setState(() => _sellerType = t),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _companyCtrl,
          decoration: const InputDecoration(
            labelText: 'Компания номи',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ownerCtrl,
          decoration: const InputDecoration(
            labelText: 'Раҳбар исми (ихтиёрий)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _registering ? null : _register,
          child: _registering
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Рўйхатдан ўтиш'),
        ),
      ],
    );
  }

  Widget _statusCard(WholesaleSeller seller) {
    final pending = seller.isPending;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pending ? Icons.hourglass_top : Icons.block,
              size: 48,
              color: pending ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              pending
                  ? 'Аризангиз кўриб чиқилмоқда'
                  : 'Аризангиз рад этилди',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (!pending && seller.adminNote.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Сабаб: ${seller.adminNote}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyProductsView extends StatelessWidget {
  const _MyProductsView({required this.seller});

  final WholesaleSeller seller;

  @override
  Widget build(BuildContext context) {
    final repo = WholesaleProductsRepository();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WholesaleProductFormScreen(seller: seller),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Янги маҳсулот'),
      ),
      body: StreamBuilder<List<WholesaleProduct>>(
        stream: repo.watchBySeller(seller.phone),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <WholesaleProduct>[];
          if (items.isEmpty) {
            return const Center(
                child: Text('Ҳали маҳсулот қўшмагансиз — «Янги маҳсулот»'));
          }
          // Расмлар AVA Дўкон (Сотувчи POS) каби — катта, cover, грид карта
          // (эга қарори, 2026-09-24). Аввал кичик CircleAvatarли ListTile эди.
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _myProductTile(context, repo, items[i]),
          );
        },
      ),
    );
  }

  Widget _myProductTile(
    BuildContext context,
    WholesaleProductsRepository repo,
    WholesaleProduct p,
  ) {
    void onMenu(String action) async {
      if (action == 'edit') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WholesaleProductFormScreen(seller: seller, existing: p),
          ),
        );
      } else if (action == 'hide') {
        await repo.deactivate(p.id);
      } else if (action == 'delete') {
        await repo.delete(p.id);
      } else if (action == 'add_video') {
        await _addVideo(context, repo, p);
      } else if (action == 'view_video') {
        await _viewVideo(context, p);
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: Colors.grey.shade100,
                      child: p.imageUrls.isEmpty
                          ? const Icon(Icons.inventory_2_outlined, size: 40)
                          : Image.network(
                              p.imageUrls.first,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  if (p.videoClipIds.isNotEmpty)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        onSelected: onMenu,
                        icon: const Icon(Icons.more_vert,
                            color: Colors.white, size: 20),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Таҳрирлаш')),
                          const PopupMenuItem(
                            value: 'add_video',
                            child: Text('🎥 Видеообзор / реклама қўшиш'),
                          ),
                          if (p.videoClipIds.isNotEmpty)
                            const PopupMenuItem(
                              value: 'view_video',
                              child: Text('Видеони кўриш'),
                            ),
                          if (p.isActive)
                            const PopupMenuItem(
                                value: 'hide', child: Text('Яшириш')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Ўчириш')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppText.bodyMedium,
                ),
              ),
            ),
            Text(
              '${p.priceTiers.length > 1 ? "дан " : ""}${formatMoney(p.basePrice)}'
              ' / ${p.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
                fontSize: AppText.titleSmall,
              ),
            ),
            Text(
              'МОҚ ${p.moq} ${p.unit} · ${_statusLabel(p.status)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// AVAGram'да видео/реклама нашр қилиш — [WholesaleVideoLink].
  Future<void> _addVideo(
    BuildContext context,
    WholesaleProductsRepository repo,
    WholesaleProduct p,
  ) async {
    try {
      final linked = await WholesaleVideoLink.publishAndLink(
        context,
        sellerPhone: seller.phone,
        productId: p.id,
      );
      if (!context.mounted || !linked) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Видео маҳсулотга боғланди')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _viewVideo(BuildContext context, WholesaleProduct p) {
    return WholesaleVideoLink.openLinkedClip(
      context,
      sellerPhone: seller.phone,
      clipIds: p.videoClipIds,
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case WholesaleProduct.statusPending:
        return 'Кутяпти';
      case WholesaleProduct.statusActive:
        return 'Фаол';
      case WholesaleProduct.statusInactive:
        return 'Яширилган';
      default:
        return status;
    }
  }
}
