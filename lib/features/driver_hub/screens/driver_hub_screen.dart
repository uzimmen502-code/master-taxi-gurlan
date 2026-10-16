import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/driver_roles.dart';
import '../../home/widgets/work_roles_sheet.dart';
import '../driver_hub_state.dart';

/// «Текширувга юбориш» натижаси.
enum HubSubmitResult { sent, alreadySent, cancelled, failed }

/// «＋» → «Ҳайдовчи / Курьер»: ҳайдовчи ва курьер учун ЯГОНА иш панели.
///
/// Экран ўзи ҳеч нарса ёзмайди ва ҳуқуқ бермайди: ҳолатни [loadRoles] /
/// [loadCar] беради, амалларни мавжуд оқимлар бажаради ([onAction],
/// [onEditCar], [onSubmitVerification], [onOpenWallet]) — параллел мантиқ
/// қурилмайди (CLAUDE.md 4, 44). Ҳар амалдан кейин ҳолат қайта ўқилади.
class DriverHubScreen extends StatefulWidget {
  const DriverHubScreen({
    super.key,
    required this.choices,
    required this.loadRoles,
    required this.loadCar,
    required this.onAction,
    required this.onEditCar,
    required this.onSubmitVerification,
    required this.onOpenWallet,
    this.onDeleteCar,
    this.onEndShift,
    this.onLeaveDriver,
    this.clock = DateTime.now,
    this.showVerification = hubShowVerification,
  });

  /// Автомобилни ўчириш (тасдиқни ўзи сўрайди). `true` — ўчирилди.
  /// `null` — тугма кўринмайди.
  final Future<bool> Function()? onDeleteCar;

  /// Сменани тугатиш (онлайн ҳайдовчи → офлайн). Тугма фақат маҳаллий ёки
  /// маршрут тури онлайн бўлганда кўринади. `null` — тугма йўқ.
  final Future<void> Function()? onEndShift;

  /// «Ҳайдовчиликдан чиқиш» (тасдиқни ўзи сўрайди). `null` — тугма йўқ.
  final Future<void> Function()? onLeaveDriver;

  /// «Текширув» карточкасини кўрсатиш (одатда [hubShowVerification] — яширин).
  final bool showVerification;

  final List<WorkChoice> choices;
  final Future<DriverRoles> Function() loadRoles;

  /// `carModel` `carColor` `carPlate` `carSeats`; `null` — киритилмаган.
  final Future<Map<String, String>?> Function() loadCar;

  /// Тур бўйича асосий амал: бўлиш / очиш / рейс эълон қилиш / ишга чиқиш.
  /// [roles] — экрандаги ЭНГ ЯНГИ ҳолат (тасдиқ керакми — шундан аниқланади).
  final Future<void> Function(WorkChoice choice, DriverRoles roles) onAction;
  final Future<void> Function() onEditCar;
  final Future<HubSubmitResult> Function() onSubmitVerification;
  final Future<void> Function() onOpenWallet;
  final DateTime Function() clock;

  @override
  State<DriverHubScreen> createState() => _DriverHubScreenState();
}

class _DriverHubScreenState extends State<DriverHubScreen> {
  DriverRoles _roles = DriverRoles.none;
  Map<String, String>? _car;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final roles = await widget.loadRoles();
      final car = await widget.loadCar();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _car = car;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Смена тугатиш: фақат онлайн бўла оладиган турлар (маҳаллий, маршрут);
  /// шаҳарлараро «фаол» — рейс, смена эмас.
  bool get _canEndShift =>
      widget.onEndShift != null &&
      (_roles.isActive('local') || _roles.isActive('marshrut'));

  bool get _canLeave => widget.onLeaveDriver != null && _roles.isDriver;

  /// Бир вақтда битта амал; тугагач ҳолат янгиланади.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _reload();
  }

  Future<void> _submitVerification() => _run(() async {
        final res = await widget.onSubmitVerification();
        if (!mounted) return;
        final key = switch (res) {
          HubSubmitResult.sent || HubSubmitResult.alreadySent => 'hub_verif_pending',
          HubSubmitResult.failed => 'hub_verif_submit_failed',
          HubSubmitResult.cancelled => null,
        };
        if (key != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.tr(key))));
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('hub_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(AvaSpace.screen),
                children: [
                  _verificationCard(context),
                  _carCard(context),
                  _sectionTitle(context, 'hub_types_title'),
                  for (final choice in widget.choices) _typeCard(context, choice),
                  const SizedBox(height: 8),
                  ListTile(
                    tileColor: c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AvaRadius.card),
                    ),
                    leading: Icon(Icons.account_balance_wallet_outlined,
                        color: c.brand),
                    title: Text(context.tr('hub_wallet')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _run(widget.onOpenWallet),
                  ),
                  if (_canEndShift) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(widget.onEndShift!),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(context.tr('end_shift')),
                    ),
                  ],
                  if (_canLeave) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      onPressed: _busy ? null : () => _run(widget.onLeaveDriver!),
                      icon: const Icon(Icons.exit_to_app),
                      label: Text(context.tr('leave_driver_permanent')),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, String key) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(context.tr(key),
            style: AvaText.sectionTitle.copyWith(color: context.ava.ink)),
      );

  Widget _card(BuildContext context, {required Widget child, Color? color}) {
    final c = context.ava;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }

  Widget _verificationCard(BuildContext context) {
    if (!widget.showVerification) return const SizedBox.shrink();
    final kind = hubVerifKind(_roles, widget.clock());
    if (kind == HubVerifKind.none) return const SizedBox.shrink();
    final c = context.ava;
    final days = _roles.starterDaysLeft(widget.clock());
    final (String text, Color tone, Color soft) = switch (kind) {
      HubVerifKind.ending => (
          context.tr('hub_verif_ending').replaceAll('{days}', '${days ?? 0}'),
          c.warn,
          c.warnSoft,
        ),
      HubVerifKind.requiredToSubmit => (
          context.tr('hub_verif_required'),
          c.warn,
          c.warnSoft,
        ),
      HubVerifKind.requiredPending => (
          context.tr('hub_verif_pending'),
          c.warn,
          c.warnSoft,
        ),
      HubVerifKind.suspended => (
          context.tr('hub_verif_suspended'),
          c.danger,
          c.dangerSoft,
        ),
      HubVerifKind.none => ('', c.ink, c.surface),
    };
    return _card(
      context,
      color: soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('hub_verif_title'),
              style: AvaText.sectionTitle.copyWith(color: tone)),
          const SizedBox(height: 4),
          Text(text, style: AvaText.body.copyWith(color: c.ink)),
          if (kind == HubVerifKind.requiredToSubmit) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _submitVerification,
              child: Text(context.tr('hub_verif_submit')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _carCard(BuildContext context) {
    final c = context.ava;
    final car = _car;
    final has = car != null &&
        (car['carModel'] ?? '').trim().isNotEmpty &&
        (car['carPlate'] ?? '').trim().isNotEmpty;
    final lines = <String>[
      if (has) ...[
        [car['carModel'], car['carColor']]
            .where((e) => (e ?? '').trim().isNotEmpty)
            .join(' · '),
        '${car['carPlate']}'
            '${(int.tryParse(car['carSeats'] ?? '') ?? 0) > 0 ? ' · ${car['carSeats']} 💺' : ''}',
      ],
    ];
    // Тугма матн ТАГИДА: ён томонда бўлса матн ингичка устунга сиқилади
    // (қурилмада топилган, 2026-10-15).
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.directions_car_outlined, color: c.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('hub_car_title'),
                        style: AvaText.sectionTitle.copyWith(color: c.ink)),
                    const SizedBox(height: 2),
                    if (has)
                      for (final l in lines)
                        Text(l, style: AvaText.body.copyWith(color: c.ink2))
                    else
                      Text(context.tr('hub_car_empty'),
                          style: AvaText.body.copyWith(color: c.ink2)),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              children: [
                if (has && widget.onDeleteCar != null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await widget.onDeleteCar!();
                            }),
                    child: Text(context.tr('delete')),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _run(widget.onEditCar),
                  child: Text(context.tr(has ? 'hub_car_edit' : 'hub_car_add')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionKey(WorkChoice choice) {
    switch (choice) {
      case WorkChoice.intercity:
        return 'hub_action_publish';
      case WorkChoice.local:
        return 'hub_action_go_work';
      case WorkChoice.marshrut:
      case WorkChoice.courier:
        return 'hub_action_open';
    }
  }

  Widget _typeCard(BuildContext context, WorkChoice choice) {
    final c = context.ava;
    final st = workRowState(choice, _roles);
    final joined = st.tone != WorkTone.join;
    final toneColor = switch (st.tone) {
      WorkTone.active => c.ok,
      WorkTone.inactive => c.ink3,
      WorkTone.pending => c.warn,
      WorkTone.blocked => c.danger,
      WorkTone.join => c.brandText,
    };
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                choice == WorkChoice.courier
                    ? Icons.delivery_dining
                    : Icons.local_taxi_outlined,
                color: c.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(choice == WorkChoice.courier
                          ? 'work_type_courier'
                          : 'role_type_${choice.name}'),
                      style: AvaText.sectionTitle.copyWith(color: c.ink),
                    ),
                    Text(context.tr(st.key),
                        style: AvaText.body.copyWith(
                            color: toneColor, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : () => _run(() => widget.onAction(choice, _roles)),
            child: Text(context.tr(joined ? _actionKey(choice) : 'work_state_join')),
          ),
        ],
      ),
    );
  }
}
