import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_tier_sheet.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';
import 'realty_pro_screen.dart';

/// «Менинг объектларим» — эга ўз эълонларини кўради ва ўчиради.
///
/// Нега керак: бепул ОДДИЙ лимити 2 та (концепция, 2-бўлим). Усиз
/// фойдаланувчи иккита ўринни банд қилиб, ортга қайта олмас эди —
/// эълони муддати тугагунча (30 кун) янгисини қўя олмасди.
///
/// Бу ерда кўринадиган объектлар лентадагидан фарқ қилади: `pending`
/// (текширувда) ва муддати тугаганлари ҳам чиқади, чунки эга улар
/// қаердалигини билиши керак.
class MyRealtyListingsScreen extends StatefulWidget {
  const MyRealtyListingsScreen({super.key});

  @override
  State<MyRealtyListingsScreen> createState() =>
      _MyRealtyListingsScreenState();
}

class _MyRealtyListingsScreenState extends State<MyRealtyListingsScreen> {
  final _repo = RealtyRepository();

  RealtyQuota _quota = RealtyQuota.empty;

  /// Гуруҳли амаллар учун белгиланганлар (концепция, 5-бўлим).
  final Set<String> _selected = {};
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    final quota = await _repo.fetchQuota();
    if (mounted) setState(() => _quota = quota);
  }

  Future<void> _bulkDelete(List<RealtyListing> all) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('realty_delete_title')),
        content: Text(
          '${_selected.length} · ${context.tr('realty_delete_body')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.tr('delete'),
              style: TextStyle(color: RealtyTabs.colorFor(RealtyTier.urgent)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkBusy = true);
    // Биттадан: сервер ҳар бирида эгалик ва квотани текширади.
    for (final id in _selected.toList()) {
      try {
        await _repo.deleteMine(id);
      } catch (_) {
        // Биттаси ўчмаса қолганлари давом этсин — рўйхат stream
        // орқали барибир ҳақиқий ҳолатни кўрсатади.
      }
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _bulkBusy = false;
    });
    await _loadQuota();
  }

  /// Белгиланганларнинг ҳаммасига бирданига РЕКЛАМА ёки СРОЧНО.
  ///
  /// Тариф варағи битта объект учун ёзилган, шунинг учун бу ерда
  /// биринчисини кўрсатамиз ва шу танловни қолганларига қўллаймиз.
  Future<void> _bulkPromote(List<RealtyListing> items) async {
    final first = items.firstWhere(
      (r) => _selected.contains(r.id),
      orElse: () => items.first,
    );
    final result = await showRealtyTierSheet(
      context,
      listing: first,
      bulkCount: _selected.length,
    );
    if (result == null || !mounted) return;

    setState(() => _bulkBusy = true);
    var failed = 0;
    for (final id in _selected.toList()) {
      if (id == first.id) continue; // варақнинг ўзи буни сотиб олди
      try {
        await _repo.purchaseTier(
          listingId: id,
          tier: result.tier,
          durationDays: result.durationDays,
        );
      } catch (_) {
        failed += 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _bulkBusy = false;
    });
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.tr('realty_bulk_failed')}: $failed'),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final repo = _repo;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? context.tr('realty_my_title')
              : '${_selected.length}',
        ),
        leading: _selected.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
        actions: [
          if (_selected.isEmpty)
            IconButton(
              tooltip: context.tr('realty_pro_title'),
              icon: const Icon(Icons.workspace_premium_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RealtyProScreen(),
                  ),
                );
                await _loadQuota();
              },
            ),
        ],
      ),
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: RealtyQuotaBar(quota: _quota),
              ),
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
                          selected: _selected.contains(items[i].id),
                          selectionMode: _selected.isNotEmpty,
                          onToggleSelect: () => setState(() {
                            final id = items[i].id;
                            if (!_selected.remove(id)) _selected.add(id);
                          }),
                          onChanged: _loadQuota,
                        ),
                      ),
              ),
              if (_selected.isNotEmpty)
                _BulkBar(
                  count: _selected.length,
                  busy: _bulkBusy,
                  onDelete: () => _bulkDelete(items),
                  onPromote: () => _bulkPromote(items),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Гуруҳли амаллар панели — белгиланганлар устида битта амал.
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.busy,
    required this.onDelete,
    required this.onPromote,
  });

  final int count;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Text(
              '${context.tr('realty_bulk_selected')}: $count',
              style: TextStyle(
                fontSize: AppText.bodySmall,
                color: c.ink2,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: busy ? null : onPromote,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text(context.tr('realty_tier_buy')),
              style: TextButton.styleFrom(
                foregroundColor: RealtyTabs.colorFor(RealtyTier.promo),
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onDelete,
              icon: busy
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
          ],
        ),
      ),
    );
  }
}
class _MyListingTile extends StatefulWidget {
  const _MyListingTile({
    required this.listing,
    required this.repo,
    required this.selected,
    required this.selectionMode,
    required this.onToggleSelect,
    required this.onChanged,
  });

  final RealtyListing listing;
  final RealtyRepository repo;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onToggleSelect;
  final VoidCallback onChanged;

  @override
  State<_MyListingTile> createState() => _MyListingTileState();
}

class _MyListingTileState extends State<_MyListingTile> {
  bool _deleting = false;

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddRealtyListingScreen(existing: widget.listing),
      ),
    );
    widget.onChanged();
  }

  /// «Нусха олиш» — янги объект, нуқта шу уйда қолади (5-бўлим).
  Future<void> _openCopy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddRealtyListingScreen(copyFrom: widget.listing),
      ),
    );
    widget.onChanged();
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

  /// Пуллик даража учун « · 5 кун» қўшимчаси; ОДДИЙда бўш.
  String _tierDaysSuffix(BuildContext context) {
    final r = widget.listing;
    final until = r.tierUntil;
    if (!r.tier.isPaid || until == null) return '';
    final days = until.difference(DateTime.now()).inDays;
    if (days < 0) return '';
    return ' · $days ${context.tr('realty_days_short')}';
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
          color: widget.selected ? c.brandSoft : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? c.brand : c.line,
            width: widget.selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              // Белгилаш режимида босиш танлайди, узоқ босиш эса
              // режимни бошлайди — гуруҳли амаллар учун (5-бўлим).
              onLongPress: widget.onToggleSelect,
              onTap: widget.selectionMode
                  ? widget.onToggleSelect
                  : () => Navigator.of(context).push(
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
                          // Пуллик даражада қанча кун қолгани ҳам ёзилади —
                          // эга узайтириш кераклигини шу ердан кўради.
                          context.tr(RealtyTabs.labelKey(r.tier)) +
                              _tierDaysSuffix(context),
                          style: TextStyle(
                            fontSize: AppText.labelTiny,
                            fontWeight: FontWeight.w600,
                            color: r.tier.isPaid
                                ? RealtyTabs.colorFor(r.tier)
                                : c.ink3,
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
            // Пуллик даража — блокланган ёки муддати тугаган объектга
            // сотилмайди (сервер ҳам рад этади, тугмани ҳам кўрсатмаймиз).
            if (!r.isExpired && r.status != 'blocked')
              TextButton.icon(
                onPressed: _deleting
                    ? null
                    : () => showRealtyTierSheet(context, listing: r),
                icon: Icon(
                  r.tier.isPaid ? Icons.autorenew : Icons.campaign_outlined,
                  size: 18,
                ),
                label: Text(
                  context.tr(
                    r.tier.isPaid ? 'realty_tier_renew' : 'realty_tier_buy',
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: RealtyTabs.colorFor(
                    r.tier.isPaid ? r.tier : RealtyTier.promo,
                  ),
                ),
              ),
            if (!r.isExpired && r.status != 'blocked')
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
                    onPressed: _deleting ? null : _openCopy,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: Text(context.tr('realty_copy')),
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
