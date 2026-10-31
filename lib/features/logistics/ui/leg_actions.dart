// AVA LOGISTICS — ижрочининг LEG амаллари (7.4 custody оқими).
//
//   new/seen      → «Жўнатмани олиш»   (`acceptLeg`, биринчи қабул — ғолиб)
//   accepted      → «Посилкани олдим»  (`scanHandover`: 6 хонали код + расм +
//                                        ҳолат белгиси — БИТТА атомар амал)
//   in_progress   → охирги LEG: «Қабул қилувчига топшердим»
//                                       (`confirmDelivery`: алоҳида код + расм)
//                   ўрта LEG:   «Кейинги ижрочига топшириш: код ва QR»
//                                       (`getShipmentSecrets` — custodian)
//   completed     → «Бажарилди» (ҳақ ҳисоб-китобдан кейин ҳамёнга)
//
// Ҳамма ҳисоб ва текширув СЕРВЕРДА (18-банд): бу виджет фақат кирим
// йиғади ва натижани кўрсатади. Хато матни `details.reason` бўйича.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../demand_offer/domain/demand_match.dart';
import '../../wholesale/models/wholesale_quote.dart' show WholesaleReturnHandoverCode;
import '../../wholesale/repositories/wholesale_orders_repository.dart';
import '../../wholesale/utils/wholesale_order_errors.dart';
import '../data/logistics_repository.dart';
import '../domain/logistics_models.dart';
import '../services/logistics_photo_storage.dart';
import '../widgets/shipment_codes_sheet.dart';
import 'logistics_text.dart';

class LogisticsLegActions extends StatefulWidget {
  const LogisticsLegActions({
    super.key,
    required this.match,
    required this.providerId,
    this.repository,
    this.photos,
    this.wholesaleRepository,
  });

  final DemandMatch match;
  final String providerId;
  final LogisticsRepository? repository;
  final LogisticsPhotoStorage? photos;

  /// Улгуржи (3b) курьер амаллари: «Харидор тўламади», қайтиш топшириш коди.
  final WholesaleOrdersRepository? wholesaleRepository;

  @override
  State<LogisticsLegActions> createState() => _LogisticsLegActionsState();
}

class _LogisticsLegActionsState extends State<LogisticsLegActions> {
  late final LogisticsRepository _repo = widget.repository ?? LogisticsRepository();
  late final LogisticsPhotoStorage _photos = widget.photos ?? LogisticsPhotoStorage();

  bool _busy = false;
  String? _error;

  /// Улгуржи (3b): LEG проекциясида буюртма ID'си йўқ — у жўнатма ҳужжатида
  /// (`shipments/{id}.wholesaleOrderId`, `source`; тайинланган ижрочи ўқийди).
  /// Оддий жўнатмада бўш қолади ва ҳеч нарса қўшилмайди.
  Shipment? _shipment;
  String _shipmentLoadedFor = '';

  DemandMatch get match => widget.match;

  @override
  void initState() {
    super.initState();
    _loadShipment();
  }

  @override
  void didUpdateWidget(covariant LogisticsLegActions old) {
    super.didUpdateWidget(old);
    _loadShipment();
  }

  Future<void> _loadShipment() async {
    final id = LegProjection.fromAttributes(match.projection.attributes).shipmentId;
    if (id.isEmpty || id == _shipmentLoadedFor) return;
    _shipmentLoadedFor = id;
    try {
      final s = await _repo.watchShipment(id).first;
      if (mounted) setState(() => _shipment = s);
    } catch (e) {
      // Ўқилмади — улгуржи амаллари кўрсатилмайди, асосий LEG оқими ишлайверади.
      debugPrint('[LegActions] shipment read failed: ${e.runtimeType}');
    }
  }

  String get _wholesaleOrderId => _shipment?.wholesaleOrderId ?? '';
  bool get _isWholesaleOutbound => _wholesaleOrderId.isNotEmpty && _shipment?.source == 'wholesale';
  bool get _isWholesaleReturn => _wholesaleOrderId.isNotEmpty && _shipment?.source == 'wholesale_return';

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final leg = LegProjection.fromAttributes(match.projection.attributes);
    final status = match.status;
    final isLast = match.contact?.deliveryCodeRequired == true || leg.isLastLeg;

    final children = <Widget>[];
    if (_error != null) {
      children.add(_errorBox(context, _error!));
      children.add(const SizedBox(height: 8));
    }

    if (status.canOffer) {
      children.add(_primary(context, 'logistics_leg_take', () => _take(leg)));
    } else if (status == MatchStatus.accepted) {
      // Улгуржи қайтиш LEG'и: «жўнатувчи» — посилка қўлидаги курьернинг ўзи,
      // топшириш кодини сервердан олади ва «Посилкани олдим» га киритади.
      if (_isWholesaleReturn) {
        children.add(_secondary(context, 'wholesale_courier_return_code_btn', _showReturnCode,
            key: const ValueKey('wholesale-courier-return-code')));
        children.add(const SizedBox(height: 8));
      }
      children.add(_primary(context, 'logistics_picked_up_btn', () => _proof(delivery: false, leg: leg)));
      children.add(const SizedBox(height: 6));
      children.add(_hint(context, 'logistics_code_hint'));
    } else if (status == MatchStatus.inProgress) {
      if (isLast) {
        children.add(_primary(context, 'logistics_delivered_btn', () => _proof(delivery: true, leg: leg)));
        // Улгуржи «етказилганда карта» буюртмаси: харидор тўламаса — курьер
        // қайд қилади (сервер карта/тўлов ҳолатини текширади; ҳамён буюртмасида рад).
        if (_isWholesaleOutbound) {
          children.add(const SizedBox(height: 8));
          children.add(_secondary(context, 'wholesale_courier_refused_btn', _markRefused,
              key: const ValueKey('wholesale-courier-refused'), danger: true));
          children.add(const SizedBox(height: 4));
          children.add(_hint(context, 'wholesale_courier_refused_hint'));
        }
      } else {
        children.add(_primary(context, 'logistics_show_code_next', () => _showCodes(leg)));
        children.add(const SizedBox(height: 6));
        children.add(_hint(context, 'logistics_next_hint'));
        final next = match.contact?.nextProviderPhone;
        if (next != null && next.isNotEmpty) {
          children.add(const SizedBox(height: 8));
          children.add(_phoneRow(context, 'logistics_next_provider_phone', next));
        }
      }
    } else if (status == MatchStatus.completed) {
      children.add(_doneBox(context));
    } else if (status.isClosed) {
      children.add(Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(12)),
        child: Text(
          context.tr('match_taken'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.ink2),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  // ── Амаллар ────────────────────────────────────────────────────────

  Future<void> _take(LegProjection leg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('logistics_leg_take')),
        content: Text(
          '${ctx.tr('logistics_leg_take_confirm')} '
          '${logisticsMoney(leg.payout)} ${ctx.tr('sum')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('consent_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('logistics_confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _repo.acceptLeg(match.demandId);
      _snack('logistics_leg_taken');
    });
  }

  Future<void> _proof({required bool delivery, required LegProjection leg}) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.ava.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ProofSheet(
        delivery: delivery,
        legId: match.demandId,
        tag: leg.trackingNumber.isNotEmpty ? leg.trackingNumber : match.demandId,
        providerId: widget.providerId,
        repository: _repo,
        photos: _photos,
      ),
    );
    if (done == true) {
      _snack(delivery ? 'logistics_delivery_done' : 'logistics_handover_done');
    }
  }

  Future<void> _showCodes(LegProjection leg) async {
    await _run(() async {
      // Проекцияда `shipmentId` бўлмаса (сервер янгиланмасидан олдинги
      // match) — сирларни олиб бўлмайди; умумий хато матни чиқади.
      if (leg.shipmentId.isEmpty) {
        throw const LogisticsException('failed-precondition', 'shipment_missing', 'shipmentId');
      }
      final s = await _repo.secrets(leg.shipmentId);
      if (!mounted) return;
      await showShipmentCodesSheet(context, s);
    });
  }

  // ── Улгуржи (3b) ───────────────────────────────────────────────────

  Future<void> _markRefused() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RefuseReasonDialog(),
    );
    if (reason == null) return; // бекор қилинди
    await _runWholesale(() async {
      await _wholesale.markBuyerRefused(orderId: _wholesaleOrderId, reason: reason);
      _snack('wholesale_courier_refused_done');
    });
  }

  Future<void> _showReturnCode() async {
    WholesaleReturnHandoverCode? code;
    await _runWholesale(() async => code = await _wholesale.returnHandoverCode(_wholesaleOrderId));
    final c = code;
    if (c == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('wholesale_courier_return_code_btn')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              c.handoverCode,
              key: const ValueKey('wholesale-courier-return-code-value'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6),
            ),
            const SizedBox(height: 8),
            Text(ctx.tr('wholesale_courier_return_code_hint'), textAlign: TextAlign.center),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('close')))],
      ),
    );
  }

  late final WholesaleOrdersRepository _wholesale = widget.wholesaleRepository ?? WholesaleOrdersRepository();

  /// Улгуржи callable хатолари — ўз матн харитаси (`wholesale_order_err_*`).
  Future<void> _runWholesale(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = wholesaleOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = logisticsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  // ── Виджетлар ──────────────────────────────────────────────────────

  Widget _primary(BuildContext context, String key, VoidCallback onTap) {
    final c = context.ava;
    return FilledButton(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(
              context.tr(key),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
    );
  }

  Widget _secondary(BuildContext context, String textKey, VoidCallback onTap, {Key? key, bool danger = false}) {
    final c = context.ava;
    return OutlinedButton(
      key: key,
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? c.danger : c.brand,
        side: BorderSide(color: danger ? c.danger : c.line),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(context.tr(textKey), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _hint(BuildContext context, String key) => Text(
        context.tr(key),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: context.ava.ink3),
      );

  Widget _errorBox(BuildContext context, String text) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 12, color: c.danger)),
    );
  }

  Widget _doneBox(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 16, color: c.ok),
              const SizedBox(width: 6),
              Text(
                context.tr('logistics_leg_done'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ok),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('logistics_leg_done_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.ink2),
          ),
        ],
      ),
    );
  }

  Widget _phoneRow(BuildContext context, String labelKey, String phone) {
    final c = context.ava;
    return InkWell(
      onTap: () => launchUrl(Uri.parse('tel:+$phone')),
      child: Row(
        children: [
          Icon(Icons.phone, size: 14, color: c.ok),
          const SizedBox(width: 6),
          Text('${context.tr(labelKey)}: ', style: TextStyle(fontSize: 12, color: c.ink2)),
          Text(
            '+$phone',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ok),
          ),
        ],
      ),
    );
  }
}

/// Custody далили варағи: код (6 рақам) + расм (мажбурий) + ҳолат белгиси.
///
/// Расм аввал Storage'га юкланади (`logistics/{ижрочи}/…`), кейин URL'лар
/// callable'га берилади — сервер расмсиз ҳодисани рад этади.
class ProofSheet extends StatefulWidget {
  const ProofSheet({
    super.key,
    required this.delivery,
    required this.legId,
    required this.tag,
    required this.providerId,
    required this.repository,
    required this.photos,
  });

  /// `true` — қабул қилувчига топшириш (алоҳида код), `false` — олиш.
  final bool delivery;
  final String legId;

  /// Расм файли номи учун (кузатув рақами).
  final String tag;
  final String providerId;
  final LogisticsRepository repository;
  final LogisticsPhotoStorage photos;

  @override
  State<ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<ProofSheet> {
  final _code = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  final Set<String> _flags = {ConditionFlags.intact};
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _code.text.length == 6 && _images.isNotEmpty;

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (x != null && mounted) setState(() => _images.add(x));
    } catch (_) {
      // Камера/галерея рад этилди — фойдаланувчи бошқа манбани танлайди.
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _uploading = true;
      _error = null;
    });
    try {
      final urls = await widget.photos.uploadHandoverPhotos(
        uploaderId: widget.providerId,
        shipmentId: widget.tag,
        images: _images,
      );
      if (mounted) setState(() => _uploading = false);
      if (widget.delivery) {
        await widget.repository.confirmDelivery(
          legId: widget.legId,
          deliveryCode: _code.text,
          photoUrls: urls,
        );
      } else {
        await widget.repository.scanHandover(
          legId: widget.legId,
          code: _code.text,
          photoUrls: urls,
          conditionFlags: _flags.toList()..sort(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploading = false;
          _error = logisticsErrorText(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr(widget.delivery ? 'logistics_delivered_btn' : 'logistics_picked_up_btn'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.ink),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr(widget.delivery ? 'logistics_enter_delivery_code' : 'logistics_enter_handover_code'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: InputDecoration(
                hintText: '••••••',
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!widget.delivery) ...[
              const SizedBox(height: 4),
              Text(context.tr('logistics_code_hint'), style: TextStyle(fontSize: 11, color: c.ink3)),
            ],
            const SizedBox(height: 16),

            Text(
              context.tr('logistics_photo_required'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _images.length; i += 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _busy ? null : () => setState(() => _images.removeAt(i)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: kIsWeb
                              ? Container(width: 72, color: c.chip, child: const Icon(Icons.image))
                              : Image.file(File(_images[i].path), width: 72, height: 72, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  _pickButton(context, Icons.photo_camera_outlined, 'logistics_take_photo', () => _pick(ImageSource.camera)),
                  const SizedBox(width: 8),
                  _pickButton(context, Icons.photo_library_outlined, 'logistics_pick_gallery', () => _pick(ImageSource.gallery)),
                ],
              ),
            ),

            if (!widget.delivery) ...[
              const SizedBox(height: 16),
              Text(
                context.tr('logistics_condition'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ConditionFlags.all)
                    ChoiceChip(
                      label: Text(context.tr(ConditionFlags.l10nKey(f))),
                      selected: _flags.contains(f),
                      selectedColor: f == ConditionFlags.intact ? c.okSoft : c.warnSoft,
                      backgroundColor: c.chip,
                      labelStyle: TextStyle(fontSize: 12, color: c.ink),
                      side: BorderSide(color: _flags.contains(f) ? c.brand : c.line),
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                // «Бутун» бошқалари билан бирга бўлмайди.
                                if (f == ConditionFlags.intact) {
                                  _flags
                                    ..clear()
                                    ..add(f);
                                } else {
                                  _flags.remove(ConditionFlags.intact);
                                  if (!_flags.remove(f)) _flags.add(f);
                                  if (_flags.isEmpty) _flags.add(ConditionFlags.intact);
                                }
                              }),
                    ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _busy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text(context.tr(_uploading ? 'logistics_uploading' : 'logistics_confirm')),
                      ],
                    )
                  : Text(
                      context.tr('logistics_confirm'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickButton(BuildContext context, IconData icon, String key, VoidCallback onTap) {
    final c = context.ava;
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c.ink2),
            const SizedBox(height: 4),
            Text(
              context.tr(key),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: c.ink2),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// «Харидор тўламади» тасдиғи + ихтиёрий сабаб. Натижа: сабаб (бўш бўлиши
/// мумкин) ёки `null` — бекор. Контроллер шу ойнанинг ўзида (ёпилиш
/// анимацияси давомида ҳам тирик).
class _RefuseReasonDialog extends StatefulWidget {
  const _RefuseReasonDialog();

  @override
  State<_RefuseReasonDialog> createState() => _RefuseReasonDialogState();
}

class _RefuseReasonDialogState extends State<_RefuseReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('wholesale_courier_refused_btn')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('wholesale_courier_refused_confirm')),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(labelText: context.tr('wholesale_courier_refused_reason')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('consent_no'))),
        FilledButton(
          key: const ValueKey('wholesale-courier-refused-yes'),
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: Text(context.tr('logistics_confirm')),
        ),
      ],
    );
  }
}