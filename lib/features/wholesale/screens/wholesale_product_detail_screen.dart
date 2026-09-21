import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_products_repository.dart';
import '../services/wholesale_video_link.dart';

/// Маҳсулот тафсилоти — улгуржи битим телефон орқали келишилади,
/// checkout/wallet йўқ (`yuk_local`даги "фақат қўнғироқ" андозаси).
class WholesaleProductDetailScreen extends StatefulWidget {
  const WholesaleProductDetailScreen({super.key, required this.product});

  final WholesaleProduct product;

  @override
  State<WholesaleProductDetailScreen> createState() =>
      _WholesaleProductDetailScreenState();
}

class _WholesaleProductDetailScreenState
    extends State<WholesaleProductDetailScreen> {
  @override
  void initState() {
    super.initState();
    WholesaleProductsRepository().incrementViews(widget.product.id);
  }

  Future<void> _call() async {
    final ok = await callPhone(widget.product.sellerId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Қўнғироқ қилиб бўлмади')),
      );
    }
  }

  Future<void> _openVideo() async {
    final ok = await WholesaleVideoLink.openLinkedClip(
      context,
      sellerPhone: widget.product.sellerId,
      clipIds: widget.product.videoClipIds,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Видео топилмади')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: Text(p.title)),
      body: ListView(
        children: [
          if (p.imageUrls.isNotEmpty)
            SizedBox(
              height: 260,
              child: PageView(
                children: [
                  for (final url in p.imageUrls)
                    Image.network(url, fit: BoxFit.cover),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    '${p.priceTiers.length > 1 ? "дан " : ""}'
                    '${p.basePrice} сўм / ${p.unit}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark)),
                const SizedBox(height: 4),
                Text('Минимал буюртма: ${p.moq} ${p.unit}',
                    style: TextStyle(color: Colors.grey.shade700)),
                if (p.priceTiers.length > 1) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Нарх поғоналари',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800)),
                        const SizedBox(height: 4),
                        for (final t in p.priceTiers)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(t.label(p.unit)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(p.description, style: const TextStyle(height: 1.4)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.storefront_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.sellerCompanyName.isEmpty
                            ? 'Сотувчи'
                            : p.sellerCompanyName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                if (p.videoClipIds.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: _openVideo,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('🎥 Видеообзорни кўриш'),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: _call,
                  icon: const Icon(Icons.call),
                  label: const Text('Қўнғироқ қилиш'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
