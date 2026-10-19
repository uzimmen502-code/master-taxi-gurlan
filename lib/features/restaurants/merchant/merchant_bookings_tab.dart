// Ресторан панели — «Бронлар» (S5, D-REST-23/38): стол бронь сўровлари. Қабул қилганда AVA хизмат ҳақи ресторан
// ҳамёнидан ечилади (аниқ сумма ҳар бронда кўринади); мижоз бекор қилса/келмаса ёки ресторан тасдиқдан кейин
// бекор қилса ҳам ҳақ қайтарилмайди (эга қарори). Ҳамёнда етмаса қабул қилиб бўлмайди — хато аниқ ёзилади.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../data/restaurants_repository.dart';
import '../domain/bookings.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;

class MerchantBookingsTab extends StatefulWidget {
  const MerchantBookingsTab({super.key, required this.restaurant, required this.repository, this.clock});

  final Restaurant restaurant;
  final RestaurantsRepository repository;
  final DateTime Function()? clock;

  @override
  State<MerchantBookingsTab> createState() => _MerchantBookingsTabState();
}

class _MerchantBookingsTabState extends State<MerchantBookingsTab> {
  late final Stream<List<RestaurantBooking>> _stream = widget.repository.watchRestaurantBookings(widget.restaurant.id);
  final Set<String> _busy = {};

  DateTime get _now => (widget.clock ?? DateTime.now)();

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _run(RestaurantBooking b, Future<String?> Function() action) async {
    setState(() => _busy.add(b.id));
    String? ok;
    Object? err;
    try {
      ok = await action();
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    setState(() => _busy.remove(b.id));
    if (err != null) {
      _snack(restaurantsErrorText(context, err), error: true);
    } else if (ok != null) {
      _snack(ok);
    }
  }

  Future<void> _accept(RestaurantBooking b) => _run(b, () async {
        await widget.repository.acceptBooking(b.id);
        return mounted ? context.tr('restaurants_m_bk_accepted_ok') : null;
      });

  Future<void> _reject(RestaurantBooking b) => _run(b, () async {
        await widget.repository.rejectBooking(b.id);
        return mounted ? context.tr('restaurants_m_bk_rejected_ok') : null;
      });

  Future<void> _cancel(RestaurantBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('restaurants_m_bk_cancel_warn')),
        actions: [
          TextButton(key: const ValueKey('bk-cancel-no'), onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('restaurants_booking_cancel_no'))),
          FilledButton(key: const ValueKey('bk-cancel-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_booking_cancel_yes'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(b, () async {
      final disabled = await widget.repository.restaurantCancelBooking(b.id);
      if (!mounted) return null;
      return context.tr(disabled ? 'restaurants_m_bk_disabled_now' : 'restaurants_m_bk_cancelled_ok');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = widget.restaurant;
    return Column(
      children: [
        if (!r.acceptsBookings || r.bookingsDisabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              key: const ValueKey('bk-off-note'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: c.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(r.bookingsDisabled ? 'restaurants_m_booking_disabled' : 'restaurants_m_bk_not_enabled'),
                      style: TextStyle(fontSize: 12, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<RestaurantBooking>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text(context.tr('restaurants_err_generic'), style: TextStyle(color: c.ink2)));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final now = _now;
              final all = snap.data!;
              bool pending(RestaurantBooking b) => b.status == BookingStatus.requested && b.startAt.isAfter(now);
              bool upcomingConfirmed(RestaurantBooking b) => b.status == BookingStatus.confirmed && b.startAt.isAfter(now);
              final fresh = all.where(pending).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
              final confirmed = all.where(upcomingConfirmed).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
              final past = all.where((b) => !pending(b) && !upcomingConfirmed(b)).toList();
              if (all.isEmpty) {
                return Center(child: Text(context.tr('restaurants_m_bk_empty'), key: const ValueKey('bk-empty'), style: TextStyle(color: c.ink2)));
              }
              Widget section(String key, List<RestaurantBooking> list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(context.tr(key), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2)),
                        ),
                        for (final b in list)
                          _Card(
                            booking: b,
                            now: now,
                            busy: _busy.contains(b.id),
                            onAccept: () => _accept(b),
                            onReject: () => _reject(b),
                            onCancel: () => _cancel(b),
                          ),
                      ],
                    );
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  section('restaurants_m_bk_new', fresh),
                  section('restaurants_m_bk_confirmed', confirmed),
                  section('restaurants_m_bk_past', past),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.booking, required this.now, required this.busy, required this.onAccept, required this.onReject, required this.onCancel});

  final RestaurantBooking booking;
  final DateTime now;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final b = booking;
    final who = b.userName.isNotEmpty ? b.userName : b.userPhone;
    return Container(
      key: ValueKey('bk-${b.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AvaRadius.card), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Booking.format(b.startAt)} · ${context.tr('restaurants_booking_guests_n').replaceAll('{n}', '${b.guests}')}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('restaurants_booking_status_${b.status}'),
                  key: ValueKey('bk-status-${b.id}'),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: b.status == BookingStatus.confirmed ? c.ok : c.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink))),
              if (b.userPhone.isNotEmpty && b.isActive)
                IconButton(
                  key: ValueKey('bk-call-${b.id}'),
                  tooltip: context.tr('restaurants_m_bk_call'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call_rounded, size: 20),
                  onPressed: () => callPhone(b.userPhone),
                ),
            ],
          ),
          if (b.note.isNotEmpty) Text(b.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (b.feeAmount > 0 && (b.isActive || b.feeCharged))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context
                    .tr(b.feeCharged ? 'restaurants_m_bk_fee_charged' : 'restaurants_m_bk_fee')
                    .replaceAll('{amount}', formatPrice(b.feeAmount)),
                key: ValueKey('bk-fee-${b.id}'),
                style: TextStyle(fontSize: 12, color: c.ink2),
              ),
            ),
          if (b.status == BookingStatus.requested && b.acceptDeadlineAt != null)
            Text(
              context.tr('restaurants_m_bk_deadline').replaceAll('{time}', _hhmm(b.acceptDeadlineAt!)),
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
          if (b.canRestaurantAnswer(now))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('bk-reject-${b.id}'),
                      onPressed: busy ? null : onReject,
                      child: Text(context.tr('restaurants_m_bk_reject')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('bk-accept-${b.id}'),
                      onPressed: busy ? null : onAccept,
                      child: Text(context.tr('restaurants_m_bk_accept')),
                    ),
                  ),
                ],
              ),
            )
          else if (b.canRestaurantCancel(now))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('bk-cancel-${b.id}'),
                onPressed: busy ? null : onCancel,
                child: Text(context.tr('restaurants_m_bk_cancel')),
              ),
            ),
        ],
      ),
    );
  }
}
