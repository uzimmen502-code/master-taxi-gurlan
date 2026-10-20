// «ФАОЛИЯТ» ТАБИ (13.4.7).
//
// Концепция: пастки навигацияда ЯГОНА «Фаолият» таби, иккита бўлим билан:
//   1) «Менинг сўровларим»     — харидор томони
//   2) «Менга келган сўровлар» — таклифчи томони
//
// Иккинчи бўлим ФАҚАТ provider йўналишини ёққан одамга кўринади.
// Акс ҳолда оддий фойдаланувчи доимо бўш таб кўриб турарди.
//
// МАНБАЛАР АЖРАТИЛГАН:
//   харидор    -> `demands` (ўз ҳужжатлари)
//   таклифчи   -> `demand_matches` (проекция)
// Таклифчи `demands`ни ҲЕЧ ҚАЧОН ўқимайди — Firestore қоидаси рад этади.

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../data/demand_repository.dart';
import '../../data/match_repository.dart';
import '../../domain/demand.dart';
import '../../domain/demand_enums.dart';
import '../../domain/demand_match.dart';
import '../../ui_adapters/demand_ui_adapter.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    required this.userId,
    required this.demandRepository,
    required this.matchRepository,
    required this.adapters,
    this.isProvider = false,
    this.onOpenDemand,
    this.onOpenMatch,
    this.onBecomeProvider,
  });

  /// Канон телефон ID (`998XXXXXXXXX`).
  final String userId;

  final DemandRepository demandRepository;
  final MatchRepository matchRepository;

  /// Модул → UI adapter. Карточкаларни adapter чизади.
  final Map<DemandModule, DemandUiAdapter> adapters;

  /// Фойдаланувчи камида битта provider йўналишини ёққанми.
  final bool isProvider;

  final void Function(Demand demand)? onOpenDemand;
  final void Function(DemandMatch match)? onOpenMatch;

  /// «Мен хизмат кўрсатаман» — таклифчи бўлиш (мустақил кириш нуқтаси).
  /// Берилмаса ва фойдаланувчи таклифчи эмас бўлса, карточка кўринмайди.
  /// Усиз уста рўйхатдан ўтолмайди: имконият экрани аввал фақат келган
  /// мослик ичидан очиларди, мослик эса имкониятсиз келмайди.
  final VoidCallback? onBecomeProvider;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.isProvider ? 2 : 1, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    // Provider эмас — фақат битта бўлим, табсиз.
    if (!widget.isProvider) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: _appBar(context),
        body: Column(
          children: [
            if (widget.onBecomeProvider != null)
              _BecomeProviderCard(onTap: widget.onBecomeProvider!),
            Expanded(
              child: _MyDemandsList(
                userId: widget.userId,
                repository: widget.demandRepository,
                onOpen: widget.onOpenDemand,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _appBar(
        context,
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.brand,
          unselectedLabelColor: c.ink2,
          indicatorColor: c.brand,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          tabs: [
            Tab(text: context.tr('activity_my_requests')),
            Tab(
              child: _IncomingTabLabel(
                userId: widget.userId,
                repository: widget.matchRepository,
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MyDemandsList(
            userId: widget.userId,
            repository: widget.demandRepository,
            onOpen: widget.onOpenDemand,
          ),
          _IncomingMatchesList(
            userId: widget.userId,
            repository: widget.matchRepository,
            adapters: widget.adapters,
            onOpen: widget.onOpenMatch,
          ),
        ],
      ),
    );
  }

  AppBar _appBar(BuildContext context, {PreferredSizeWidget? bottom}) {
    final c = context.ava;
    return AppBar(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface,
      elevation: 0,
      title: Text(
        context.tr('activity_tab'),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: c.ink,
        ),
      ),
      bottom: bottom,
    );
  }
}

/// «Хизмат кўрсатасизми?» — таклифчи бўлишга таклиф (таклифчи бўлмаганларга).
class _BecomeProviderCard extends StatelessWidget {
  const _BecomeProviderCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.handyman_rounded, color: c.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('activity_become_provider_title'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('activity_become_provider_sub'),
                        style: TextStyle(fontSize: 12, color: c.ink2),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Менга келган сўровлар» таби — янги сўровлар сони билан.
class _IncomingTabLabel extends StatelessWidget {
  const _IncomingTabLabel({required this.userId, required this.repository});

  final String userId;
  final MatchRepository repository;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<int>(
      stream: repository.newMatchCount(userId),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.tr('activity_incoming')),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  n > 99 ? '99+' : '$n',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: c.brandInk,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Харидор томони — «Менинг сўровларим».
class _MyDemandsList extends StatelessWidget {
  const _MyDemandsList({
    required this.userId,
    required this.repository,
    this.onOpen,
  });

  final String userId;
  final DemandRepository repository;
  final void Function(Demand demand)? onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Demand>>(
      stream: repository.myDemands(userId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const <Demand>[];
        if (list.isEmpty) {
          return _EmptyState(messageKey: 'activity_empty_my');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _MyDemandTile(
            demand: list[i],
            onTap: onOpen == null ? null : () => onOpen!(list[i]),
          ),
        );
      },
    );
  }
}

/// Битта сўров — қисқа ҳолат билан.
///
/// Концепция: «Ҳар бир талаб учун қисқа ҳолат: "30+ мос сотувчига
/// юборилди", "3 та таклиф".»
class _MyDemandTile extends StatelessWidget {
  const _MyDemandTile({required this.demand, this.onTap});

  final Demand demand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    demand.title.isNotEmpty
                        ? demand.title
                        : context.tr('request_create_title'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: demand.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people_outline, size: 13, color: c.ink3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    // Т-8: АНИҚ РАҚАМ ЭМАС, панжара.
                    demand.matching.state.showsWaitingMessage
                        ? context.tr('request_no_providers')
                        : '${demand.matching.matchedBucket} '
                            '${context.tr('request_sent_to')}',
                    style: TextStyle(fontSize: 11, color: c.ink2),
                    maxLines: 2,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DemandStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final (bg, fg) = switch (status) {
      DemandStatus.active => (c.brandSoft, c.brand),
      DemandStatus.accepted || DemandStatus.inProgress => (c.okSoft, c.ok),
      DemandStatus.completed => (c.okSoft, c.ok),
      DemandStatus.cancelled || DemandStatus.expired => (c.chip, c.ink3),
      DemandStatus.disputed => (c.dangerSoft, c.danger),
      DemandStatus.draft => (c.chip, c.ink3),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        // Техник сўз ЙЎҚ — фойдаланувчи тилида («Таклиф кутилмоқда»).
        context.tr(status.l10nKey),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Таклифчи томони — «Менга келган сўровлар».
class _IncomingMatchesList extends StatelessWidget {
  const _IncomingMatchesList({
    required this.userId,
    required this.repository,
    required this.adapters,
    this.onOpen,
  });

  final String userId;
  final MatchRepository repository;
  final Map<DemandModule, DemandUiAdapter> adapters;
  final void Function(DemandMatch match)? onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DemandMatch>>(
      stream: repository.myMatches(userId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const <DemandMatch>[];
        if (list.isEmpty) {
          return _EmptyState(messageKey: 'activity_empty_incoming');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = list[i];
            final adapter = adapters[m.module];
            return InkWell(
              onTap: () {
                // «Кўрдим» — такрор push камайтириш ва аналитика учун.
                repository.markSeen(m.demandId, m.providerId);
                onOpen?.call(m);
              },
              borderRadius: BorderRadius.circular(14),
              child: adapter != null
                  ? adapter.buildMatchCard(context, m)
                  : _FallbackMatchTile(match: m),
            );
          },
        );
      },
    );
  }
}

/// Adapter'и йўқ модул учун — илова йиқилмайди.
///
/// Сервер янги модулни ёқса, эски илова уни ҳам кўрсата олиши керак.
class _FallbackMatchTile extends StatelessWidget {
  const _FallbackMatchTile({required this.match});

  final DemandMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Text(
        match.projection.title.isNotEmpty
            ? match.projection.title
            : context.tr('activity_incoming'),
        style: TextStyle(fontSize: 13, color: c.ink),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: c.ink3),
            const SizedBox(height: 10),
            Text(
              context.tr(messageKey),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
