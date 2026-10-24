// «Менинг бронларим» (S5): мижознинг стол бронлари — яқинлашаётганлар, ўтган ва бекор қилинганлар.
// Бекор қилиш — мижоз ҳам фаол бронни бекор қила олади (ҳақ мижозники эмас: ресторан тўлаган бўлса қайтмайди).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../domain/bookings.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key, required this.uid, this.repository, this.clock});

  /// 12 рақамли телефон (бронлар `userPhone` бўйича сўралади).
  final String uid;
  final RestaurantsRepository? repository;
  final DateTime Function()? clock;

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late final Stream<List<RestaurantBooking>> _stream = _repo.watchMyBookings(widget.uid);
  final Set<String> _busy = {};

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<void> _cancel(RestaurantBooking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_booking_cancel_confirm')),
        actions: [
          TextButton(key: const ValueKey('cancel-no'), onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('restaurants_booking_cancel_no'))),
          FilledButton(key: const ValueKey('cancel-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_booking_cancel_yes'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(b.id));
    String? text;
    try {
      await _repo.guestCancelBooking(b.id);
      if (mounted) text = context.tr('restaurants_booking_cancelled_ok');
    } catch (e) {
      if (mounted) text = restaurantsErrorText(context, e);
    }
    if (!mounted) return;
    setState(() => _busy.remove(b.id));
    if (text != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr('restaurants_booking_my'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: StreamBuilder<List<RestaurantBooking>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(context.tr('restaurants_err_generic'), style: TextStyle(color: c.ink2)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final now = _now;
          final all = snap.data!;
          final upcoming = all.where((b) => b.isActive && b.startAt.isAfter(now)).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
          final past = all.where((b) => !(b.isActive && b.startAt.isAfter(now))).toList();
          if (all.isEmpty) {
            return Center(child: Text(context.tr('restaurants_booking_empty'), key: const ValueKey('bookings-empty'), style: TextStyle(color: c.ink2)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              if (upcoming.isNotEmpty) _Header(context.tr('restaurants_booking_upcoming')),
              for (final b in upcoming) _BookingCard(booking: b, now: now, busy: _busy.contains(b.id), onCancel: () => _cancel(b)),
              if (past.isNotEmpty) _Header(context.tr('restaurants_booking_past')),
              for (final b in past) _BookingCard(booking: b, now: now, busy: false, onCancel: null),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ava.ink2)),
      );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.now, required this.busy, required this.onCancel});

  final RestaurantBooking booking;
  final DateTime now;
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final b = booking;
    final color = switch (b.status) {
      BookingStatus.confirmed => c.ok,
      BookingStatus.requested => c.warn,
      _ => c.ink2,
    };
    return Container(
      key: ValueKey('booking-${b.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AvaRadius.card), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(b.restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    context.tr('restaurants_booking_status_${b.status}'),
                    key: ValueKey('booking-status-${b.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${Booking.format(b.startAt)} · ${context.tr('restaurants_booking_guests_n').replaceAll('{n}', '${b.guests}')}',
            style: TextStyle(fontSize: 13, color: c.ink),
          ),
          if (b.restaurantAddress.isNotEmpty) Text(b.restaurantAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (b.note.isNotEmpty) Text(b.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (b.status != BookingStatus.rejected && b.bookingNote.isNotEmpty && b.isActive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(b.bookingNote, key: ValueKey('booking-cafe-note-${b.id}'), style: TextStyle(fontSize: 12, color: c.ink2)),
            ),
          if (onCancel != null && b.canGuestCancel(now))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('booking-cancel-${b.id}'),
                onPressed: busy ? null : onCancel,
                child: Text(context.tr('restaurants_booking_cancel')),
              ),
            ),
        ],
      ),
    );
  }
}
