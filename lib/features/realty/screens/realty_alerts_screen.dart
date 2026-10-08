import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_alert.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../widgets/realty_card.dart';
import '../widgets/realty_feedback.dart';
import 'realty_alert_form_screen.dart';
import 'realty_detail_screen.dart';

/// 🔔 «Шундай уй чиқса, хабар бер» — ижарачининг бўлими (эга қарори
/// 2026-10-08). Икки таб:
///   • «Мос эълонлар» — сервер мослаб ёзган рўйхат (push келган эълонлар);
///   • «Хабарномаларим» — тўхтатиш, қайта ёқиш (+30 кун), ўчириш.
/// Мос эълон очилганда аввалгидек ПАКЕТ орқали контакт очилади — бу
/// бўлим пуллик моделни ўзгартирмайди.
class RealtyAlertsScreen extends StatefulWidget {
  const RealtyAlertsScreen({super.key, this.repository});

  final RealtyRepository? repository;

  @override
  State<RealtyAlertsScreen> createState() => _RealtyAlertsScreenState();
}

class _RealtyAlertsScreenState extends State<RealtyAlertsScreen>
    with SingleTickerProviderStateMixin {
  late final RealtyRepository _repo = widget.repository ?? RealtyRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _newAlert() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await Navigator.of(context).push<RealtyAlertCreateResult>(
      MaterialPageRoute(
        builder: (_) => RealtyAlertFormScreen(repository: widget.repository),
      ),
    );
    if (res == null || !mounted) return;
    _tabs.animateTo(1);
    final n = res.matchIds.length;
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(n > 0
          ? context.tr('realty_alert_saved_with_matches').replaceAll('{n}', '$n')
          : context.tr('realty_alert_saved')),
      action: n > 0
          ? SnackBarAction(
              label: context.tr('realty_alert_show'),
              onPressed: () => _openCurrent(res.matchIds),
            )
          : null,
    ));
  }

  void _openCurrent(List<String> ids) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CurrentMatchesScreen(repo: _repo, ids: ids),
    ));
  }

  Future<void> _openMatch(RealtyMatch m) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final notFound = context.tr('realty_alert_listing_gone');
    if (!m.seen) _repo.markMatchSeen(m.listingId);
    final listing = await _repo.fetchListing(m.listingId);
    if (listing == null) {
      showRealtyInfo(messenger, notFound);
      return;
    }
    nav.push(MaterialPageRoute(
      builder: (_) => RealtyDetailScreen(listing: listing),
    ));
  }

  Future<void> _setStatus(RealtyAlert a, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.setAlertStatus(a.id, status);
    } on RealtyException catch (e) {
      if (!mounted) return;
      showRealtyError(messenger, realtyErrorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('realty_alerts_title')),
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.brandInk,
          unselectedLabelColor: c.brandInk.withValues(alpha: 0.65),
          indicatorColor: c.brandInk,
          tabs: [
            Tab(text: context.tr('realty_alerts_tab_matches')),
            Tab(text: context.tr('realty_alerts_tab_mine')),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('realty_alert_new'),
        onPressed: _newAlert,
        icon: const Icon(Icons.add_alert_outlined),
        label: Text(context.tr('realty_alert_new_title')),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          StreamBuilder<List<RealtyMatch>>(
            stream: _repo.watchMyMatches(),
            builder: (context, snap) {
              final items = snap.data ?? const <RealtyMatch>[];
              if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return _Empty(text: context.tr('realty_alerts_matches_empty'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _MatchTile(match: items[i], onTap: _openMatch),
              );
            },
          ),
          StreamBuilder<List<RealtyAlert>>(
            stream: _repo.watchMyAlerts(),
            builder: (context, snap) {
              final items = snap.data ?? const <RealtyAlert>[];
              if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return _Empty(text: context.tr('realty_alerts_mine_empty'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _AlertTile(alert: items[i], onStatus: _setStatus),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ava.ink2, fontSize: AppText.bodyMedium),
          ),
        ),
      );
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onTap});
  final RealtyMatch match;
  final void Function(RealtyMatch) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sub = [
      if (match.rooms != null) '${match.rooms} ${context.tr('realty_alert_rooms_short')}',
      if (match.priceText.trim().isNotEmpty) match.priceText.trim(),
    ].join(' · ');
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: () => onTap(match),
        leading: Icon(
          match.seen ? Icons.home_outlined : Icons.fiber_new_rounded,
          color: match.seen ? c.ink3 : c.brand,
        ),
        title: Text(
          match.title.isEmpty ? context.tr('realty_detail_title') : match.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: match.seen ? FontWeight.w500 : FontWeight.w800,
            color: c.ink,
          ),
        ),
        subtitle: sub.isEmpty ? null : Text(sub),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.onStatus});
  final RealtyAlert alert;
  final Future<void> Function(RealtyAlert, String) onStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final a = alert;
    final rooms = a.roomsMin == null
        ? ''
        : (a.roomsMax == null
            ? '${a.roomsMin}+ ${context.tr('realty_alert_rooms_short')}'
            : (a.roomsMin == a.roomsMax
                ? '${a.roomsMin} ${context.tr('realty_alert_rooms_short')}'
                : '${a.roomsMin}–${a.roomsMax} ${context.tr('realty_alert_rooms_short')}'));
    final parts = [
      context.tr(a.deal == RealtyDeal.rent ? 'realty_deal_rent' : 'realty_deal_sale'),
      '${a.radiusKm} км',
      if (rooms.isNotEmpty) rooms,
      if (a.priceMax != null) '≤ ${a.priceMax} сўм',
    ];
    final statusKey = a.isExpired
        ? 'realty_alert_status_expired'
        : (a.status == 'paused' ? 'realty_alert_status_paused' : 'realty_alert_status_active');
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: Icon(
          a.isActive ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          color: a.isActive ? c.brand : c.ink3,
        ),
        title: Text(parts.join(' · '), style: TextStyle(color: c.ink)),
        subtitle: Text(context.tr(statusKey)),
        trailing: PopupMenuButton<String>(
          onSelected: (s) => onStatus(a, s),
          itemBuilder: (_) => [
            if (!a.isActive)
              PopupMenuItem(value: 'active', child: Text(context.tr('realty_alert_action_resume'))),
            if (a.isActive)
              PopupMenuItem(value: 'paused', child: Text(context.tr('realty_alert_action_pause'))),
            PopupMenuItem(value: 'deleted', child: Text(context.tr('realty_alert_action_delete'))),
          ],
        ),
      ),
    );
  }
}

/// Хабарнома сақланган пайтда ҲОЗИР мос келадиган эълонлар.
class _CurrentMatchesScreen extends StatelessWidget {
  const _CurrentMatchesScreen({required this.repo, required this.ids});
  final RealtyRepository repo;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ava.bg,
      appBar: AppBar(title: Text(context.tr('realty_alerts_tab_matches'))),
      body: FutureBuilder<List<RealtyListing>>(
        future: repo.fetchListings(ids),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return _Empty(text: context.tr('realty_alerts_matches_empty'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => RealtyCard(
              listing: items[i],
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RealtyDetailScreen(listing: items[i]),
              )),
            ),
          );
        },
      ),
    );
  }
}
