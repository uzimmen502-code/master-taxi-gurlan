// «ТАЛАБ ВА ТАКЛИФЛАР» — ПРОФИЛЬДАН КИРИШ НУҚТАСИ.
//
// Эга қарори (2026-10-03): пастки навигацияга янги таб ҚЎШИЛМАЙДИ,
// бўлим Профиль ичида туради.
//
// Бу виджетнинг вазифаси — репозиторий ва adapter'ларни ЙИҒИШ, шунда
// `profile_screen.dart` ядронинг ички тузилишини билмайди. Профиль
// экрани 45 КБ, унга яна боғламлар қўшиш нотўғри бўларди.
//
// `isProvider` аниқланади: фойдаланувчи камида битта актив имкониятга
// эга бўлсагина «Менга келган сўровлар» бўлими кўринади. Акс ҳолда
// оддий фойдаланувчи доимо бўш таб кўриб турарди.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/demand_repository.dart';
import '../../data/match_repository.dart';
import '../../domain/demand.dart';
import '../../domain/demand_enums.dart';
import '../../domain/demand_match.dart';
import '../../ui_adapters/demand_ui_adapter.dart';
import '../../ui_adapters/service_ui_adapter.dart';
import '../demand_detail/demand_detail_screen.dart';
import '../demand_detail/demand_match_detail_screen.dart';
import 'activity_screen.dart';

/// Ядрога уланган модулларнинг UI adapter'лари.
///
/// P0'да биттаси (Қ-1). Янги модул қўшилганда фақат шу жадвал ўсади.
const Map<DemandModule, DemandUiAdapter> kDemandUiAdapters = {
  DemandModule.service: ServiceUiAdapter(),
};

class DemandActivityEntry extends StatefulWidget {
  const DemandActivityEntry({
    super.key,
    required this.userId,
    this.firestore,
    this.demandRepository,
    this.matchRepository,
  });

  /// Канон телефон ID (`998XXXXXXXXX`).
  final String userId;

  final FirebaseFirestore? firestore;
  final DemandRepository? demandRepository;
  final MatchRepository? matchRepository;

  @override
  State<DemandActivityEntry> createState() => _DemandActivityEntryState();
}

class _DemandActivityEntryState extends State<DemandActivityEntry> {
  late final DemandRepository _demands;
  late final MatchRepository _matches;
  bool? _isProvider;

  @override
  void initState() {
    super.initState();
    _demands = widget.demandRepository ?? DemandRepository();
    _matches = widget.matchRepository ?? MatchRepository();
    _checkProvider();
  }

  /// Фойдаланувчи камида битта актив имкониятга эгами.
  ///
  /// ШАКЛ ЎЗГАРДИ (D-12…D-16): аввал `provider_capabilities` да ҳар бир
  /// (uid, модул) жуфти учун алоҳида ҳужжат бор эди ва бу ерда
  /// `where('providerId', ...)` сўрови ишлатиларди. Энди битта uid =
  /// битта ҳужжат, шунинг учун ҚЎШИМЧА ФОЙДА ҳам бор: сўров эмас,
  /// битта `get` — арзонроқ ва янги қоидага мос (`isOwner(uid)` сўров
  /// билан қондирилмайди, яъни эски код `permission-denied` оларди ва
  /// таклифчи бўлими ЖИМГИНА йўқоларди).
  Future<void> _checkProvider() async {
    final db = widget.firestore ?? FirebaseFirestore.instance;
    try {
      // T-1a: capability калити — `users/{uid}.accountId` (сервер
      // беради). accountId йўқ = ҳали бирорта хизмат ёқилмаган.
      final user = await db.collection('users').doc(widget.userId).get();
      final accountId = user.data()?['accountId']?.toString() ?? '';
      if (accountId.isEmpty) {
        if (mounted) setState(() => _isProvider = false);
        return;
      }
      final snap =
          await db.collection('provider_capabilities').doc(accountId).get();
      final data = snap.data() ?? const <String, dynamic>{};
      // Хизмат рўйхати `DemandModule` дан олинади — такрорланмасин.
      final hasActive = DemandModule.values.any((m) {
        final svc = data[m.wire];
        return svc is Map && svc['active'] == true;
      });
      if (mounted) setState(() => _isProvider = hasActive);
    } catch (_) {
      // Текширув йиқилса таклифчи бўлими кўрсатилмайди — харидор
      // бўлими барибир ишлайди, экран бўш қолмайди.
      if (mounted) setState(() => _isProvider = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isProvider == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return ActivityScreen(
      userId: widget.userId,
      demandRepository: _demands,
      matchRepository: _matches,
      adapters: kDemandUiAdapters,
      isProvider: _isProvider!,
      onOpenDemand: _openDemand,
      onOpenMatch: _openMatch,
    );
  }

  void _openDemand(Demand demand) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DemandDetailScreen(
          demandId: demand.id,
          repository: _demands,
          adapters: kDemandUiAdapters,
        ),
      ),
    );
  }

  void _openMatch(DemandMatch match) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DemandMatchDetailScreen(
          demandId: match.demandId,
          providerId: match.providerId,
          repository: _matches,
          adapters: kDemandUiAdapters,
        ),
      ),
    );
  }
}
