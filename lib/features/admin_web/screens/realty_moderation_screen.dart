import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_realty_service.dart';

/// 🏠 Кўчмас мулк модерацияси.
///
/// Нега керак: `realtyAutoApprove` ёқиқ бўлганда эълонлар текширувсиз
/// лентага тушади. Алдов ёки нотўғри эълонни олиб ташлашнинг ягона
/// йўли Firestore консоли бўлиб қолмаслиги учун шу экран бор.
class RealtyModerationScreen extends StatefulWidget {
  const RealtyModerationScreen({super.key});

  @override
  State<RealtyModerationScreen> createState() => _RealtyModerationScreenState();
}

class _RealtyModerationScreenState extends State<RealtyModerationScreen> {
  final _repo = RealtyRepository();

  /// null — ҳамма ёзув.
  String? _status = 'pending';

  static const _filters = <(String?, String)>[
    ('pending', 'Текширувда'),
    ('active', 'Фаол'),
    ('blocked', 'Блокланган'),
    (null, 'Ҳаммаси'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in _filters)
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _status == f.$1,
                  onSelected: (_) => setState(() => _status = f.$1),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<RealtyListing>>(
            stream: _repo.watchForModeration(status: _status),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Хатолик: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return const Center(child: Text('Эълон йўқ.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) => _ListingTile(listing: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ListingTile extends StatefulWidget {
  const _ListingTile({required this.listing});

  final RealtyListing listing;

  @override
  State<_ListingTile> createState() => _ListingTileState();
}

class _ListingTileState extends State<_ListingTile> {
  final _svc = AdminRealtyService();
  bool _busy = false;

  String get _adminPhone =>
      context.read<AdminAuthService>().phoneDigits ?? '';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Эълонни ўчириш'),
        content: const Text(
          'Ёзув базадан бутунлай ўчирилади. Қайтариб бўлмайди.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Бекор қилиш'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _svc.deleteListing(
          adminPhone: _adminPhone,
          listingId: widget.listing.id,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.listing;
    final blocked = r.status == 'blocked';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _chip(r.status),
                const SizedBox(width: 6),
                _chip(r.tier.key),
                const SizedBox(width: 6),
                _chip(r.deal.key),
                const Spacer(),
                Text(
                  r.ownerPhone,
                  style: const TextStyle(fontSize: AppText.labelSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              r.titleOrText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (r.priceText.isNotEmpty) Text(r.priceText),
            if (r.specsLabel.isNotEmpty)
              Text(
                r.specsLabel,
                style: const TextStyle(fontSize: AppText.bodySmall),
              ),
            const SizedBox(height: 4),
            Text(
              r.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppText.bodySmall),
            ),
            const SizedBox(height: 4),
            Text(
              'Координата: ${r.lat.toStringAsFixed(5)}, '
              '${r.lng.toStringAsFixed(5)}'
              '${r.addressText.isEmpty ? '' : ' · ${r.addressText}'}',
              style: const TextStyle(fontSize: AppText.labelSmall),
            ),
            if (r.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      r.imageUrls[i],
                      width: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 96),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (r.status != 'active')
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _svc.setStatus(
                              adminPhone: _adminPhone,
                              listingId: r.id,
                              status: 'active',
                            )),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Тасдиқлаш'),
                  ),
                if (!blocked)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _svc.setStatus(
                              adminPhone: _adminPhone,
                              listingId: r.id,
                              status: 'blocked',
                            )),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Блоклаш'),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _confirmDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Ўчириш'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: AppText.labelTiny),
        ),
      );
}
