import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';

/// «Менинг объектларим» — эга ўз эълонларини кўради ва ўчиради.
///
/// Нега керак: бепул ОДДИЙ лимити 2 та (концепция, 2-бўлим). Усиз
/// фойдаланувчи иккита ўринни банд қилиб, ортга қайта олмас эди —
/// эълони муддати тугагунча (30 кун) янгисини қўя олмасди.
///
/// Бу ерда кўринадиган объектлар лентадагидан фарқ қилади: `pending`
/// (текширувда) ва муддати тугаганлари ҳам чиқади, чунки эга улар
/// қаердалигини билиши керак.
class MyRealtyListingsScreen extends StatelessWidget {
  const MyRealtyListingsScreen({super.key});

  /// Бепул ўринни банд қилиб турган объектлар — сервердаги
  /// `countActivePlain` билан бир хил ҳисоб.
  static int usedFreeSlots(List<RealtyListing> items) => items
      .where((r) =>
          r.tier == RealtyTier.plain && r.status != 'blocked' && !r.isExpired)
      .length;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final repo = RealtyRepository();
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_my_title'))),
      body: StreamBuilder<List<RealtyListing>>(
        stream: repo.watchMine(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('realty_feed_error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.ink2),
                ),
              ),
            );
          }
          final items = snap.data ?? const <RealtyListing>[];
          final used = usedFreeSlots(items);
          return Column(
            children: [
              _FreeSlotsBar(used: used),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.tr('realty_my_empty'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.ink2,
                              fontSize: AppText.bodyMedium,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _MyListingTile(
                          listing: items[i],
                          repo: repo,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// «Бепул ўрин: 1 / 2» — эга нечта ўрни қолганини доим кўриб турсин.
class _FreeSlotsBar extends StatelessWidget {
  const _FreeSlotsBar({required this.used});

  final int used;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final full = used >= RealtyTierX.freePlainLimit;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: full ? RealtyTabs.colorFor(RealtyTier.urgent) : c.line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            full ? Icons.info_outline : Icons.check_circle_outline,
            size: 18,
            color: full ? RealtyTabs.colorFor(RealtyTier.urgent) : c.ink3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('realty_my_free_slots')}: '
              '$used / ${RealtyTierX.freePlainLimit}',
              style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyListingTile extends StatefulWidget {
  const _MyListingTile({required this.listing, required this.repo});

  final RealtyListing listing;
  final RealtyRepository repo;

  @override
  State<_MyListingTile> createState() => _MyListingTileState();
}

class _MyListingTileState extends State<_MyListingTile> {
  bool _deleting = false;

  void _openEdit() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddRealtyListingScreen(existing: widget.listing),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr('realty_delete_title')),
        content: Text(context.tr('realty_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              context.tr('delete'),
              style: TextStyle(color: RealtyTabs.colorFor(RealtyTier.urgent)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repo.deleteMine(widget.listing.id);
      if (!mounted) return;
      // Рўйхат stream орқали ўзи янгиланади — қўлда олиб ташлаш керак эмас.
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_deleted')),
        behavior: SnackBarBehavior.floating,
      ));
    } on RealtyException {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_delete_failed')),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// «Қолди: 12 кун» ёки «Муддати тугаган».
  String _expiryLabel(BuildContext context) {
    final r = widget.listing;
    if (r.isExpired) return context.tr('realty_expired');
    final exp = r.expiresAt;
    if (exp == null) return '';
    final days = exp.difference(DateTime.now()).inDays;
    if (days <= 0) return context.tr('realty_expires_today');
    return '${context.tr('realty_expires_in')}: $days '
        '${context.tr('realty_days_short')}';
  }

  ({String key, Color color}) _statusChip(BuildContext context) {
    switch (widget.listing.status) {
      case 'pending':
        return (
          key: 'realty_status_pending',
          color: RealtyTabs.colorFor(RealtyTier.promo),
        );
      case 'blocked':
        return (
          key: 'realty_status_blocked',
          color: RealtyTabs.colorFor(RealtyTier.urgent),
        );
      default:
        return (
          key: 'realty_status_active',
          color: RealtyTabs.colorFor(RealtyTier.plain),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = widget.listing;
    final chip = _statusChip(context);
    final expiry = _expiryLabel(context);
    return Opacity(
      opacity: r.isExpired ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RealtyDetailScreen(listing: r),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: chip.color,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            context.tr(chip.key),
                            style: const TextStyle(
                              fontSize: AppText.labelTiny,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr(RealtyTabs.labelKey(r.tier)),
                          style: TextStyle(
                            fontSize: AppText.labelTiny,
                            fontWeight: FontWeight.w600,
                            color: c.ink3,
                          ),
                        ),
                        const Spacer(),
                        if (expiry.isNotEmpty)
                          Text(
                            expiry,
                            style: TextStyle(
                              fontSize: AppText.labelTiny,
                              color: c.ink3,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      r.titleOrText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (r.priceText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.priceText,
                        style: TextStyle(
                          fontSize: AppText.bodyMedium,
                          fontWeight: FontWeight.w700,
                          color: RealtyTabs.colorFor(r.tier),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: c.line),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _deleting ? null : _openEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(context.tr('edit')),
                    style: TextButton.styleFrom(foregroundColor: c.ink2),
                  ),
                ),
                SizedBox(height: 28, child: VerticalDivider(color: c.line)),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _deleting ? null : _confirmDelete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: Text(context.tr('delete')),
                    style: TextButton.styleFrom(
                      foregroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
