// Стол бронь варағи (S5, D-REST-23/38): кун · вақт · меҳмонлар сони · изоҳ → «Бронь сўровини юбориш».
//
// Нарх/ҳақ мижозга кўрсатилмайди (ҳақни ресторан тўлайди — эга, 2026-10-19). Ҳақиқий текширув, сиғим ва пул —
// серверда (`placeRestaurantBooking`); бу ерда фақат тугмани ўчириш ва аниқ хато матни учун [Booking.check].
// Идемпотент калит варақ очилганда БИР МАРТА яратилади: такрор босиш/тармоқ қайта юбориши иккинчи бронь қилмайди.

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../domain/bookings.dart';
import '../domain/restaurant_models.dart';
import 'restaurant_checkout_sheet.dart' show restaurantsErrorText;

/// Варақни очади. `true` — сўров юборилди; `null`/`false` — ёпилди.
Future<bool?> showBookingSheet(
  BuildContext context, {
  required Restaurant restaurant,
  required BookingConfig config,
  required RestaurantsRepository repository,
  DateTime Function()? clock,
}) {
  final c = context.ava;
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: c.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: BookingSheet(restaurant: restaurant, config: config, repository: repository, clock: clock),
    ),
  );
}

class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.restaurant, required this.config, required this.repository, this.clock});

  final Restaurant restaurant;
  final BookingConfig config;
  final RestaurantsRepository repository;

  /// Тест учун соат.
  final DateTime Function()? clock;

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final _note = TextEditingController();
  late final String _key = const Uuid().v4();
  late DateTime _now = (widget.clock ?? DateTime.now)();
  late DateTime _start = Booking.suggest(_now, widget.config);
  int _guests = 2;
  bool _busy = false;
  String? _serverError;

  Restaurant get _r => widget.restaurant;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _maxGuests {
    final byTier = widget.config.maxGuests;
    return _r.bookingSeats > 0 && _r.bookingSeats < byTier ? _r.bookingSeats : byTier;
  }

  String? get _problem =>
      Booking.check(now: _now, start: _start, guests: _guests, restaurant: _r, config: widget.config);

  String _two(int n) => n.toString().padLeft(2, '0');

  String _dayLabel(BuildContext context, DateTime d) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return context.tr('restaurants_preorder_today');
    if (diff == 1) return context.tr('restaurants_preorder_tomorrow');
    return '${_two(d.day)}.${_two(d.month)}';
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && mounted) {
      setState(() {
        _serverError = null;
        _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      });
    }
  }

  Future<void> _submit() async {
    if (_busy || _problem != null) return;
    setState(() {
      _busy = true;
      _serverError = null;
      _now = (widget.clock ?? DateTime.now)();
    });
    try {
      await widget.repository.placeBooking(
        idempotencyKey: _key,
        restaurantId: _r.id,
        guests: _guests,
        startAt: _start,
        note: _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = restaurantsErrorText(context, e);
      });
    }
  }

  String _problemText(BuildContext context, String key) => context
      .tr('restaurants_booking_err_$key')
      .replaceAll('{min}', '${widget.config.minLeadMin}')
      .replaceAll('{days}', '${widget.config.maxDays}')
      .replaceAll('{max}', '${widget.config.maxGuests}')
      .replaceAll('{seats}', '${_r.bookingSeats}');

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final problem = _problem;
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('restaurants_booking_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 2),
            Text(_r.name, style: TextStyle(fontSize: 13, color: c.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Text(context.tr('restaurants_booking_day'), style: label),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                key: const ValueKey('booking-days'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final d in Booking.days(_now, widget.config)) ...[
                    ChoiceChip(
                      key: ValueKey('booking-day-${d.year}-${d.month}-${d.day}'),
                      label: Text(_dayLabel(context, d)),
                      selected: d.year == _start.year && d.month == _start.month && d.day == _start.day,
                      onSelected: (_) => setState(() {
                        _serverError = null;
                        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(context.tr('restaurants_booking_time'), style: label),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('booking-time'),
                onPressed: _busy ? null : _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text('${_two(_start.hour)}:${_two(_start.minute)}'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text(context.tr('restaurants_booking_guests'), style: label)),
                IconButton(
                  key: const ValueKey('booking-guests-minus'),
                  onPressed: _busy || _guests <= 1 ? null : () => setState(() => _guests -= 1),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                SizedBox(
                  width: 40,
                  child: Text('$_guests', key: const ValueKey('booking-guests'), textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
                ),
                IconButton(
                  key: const ValueKey('booking-guests-plus'),
                  onPressed: _busy || _guests >= _maxGuests ? null : () => setState(() => _guests += 1),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            TextField(
              key: const ValueKey('booking-note'),
              controller: _note,
              maxLength: 200,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: context.tr('restaurants_booking_note'),
                hintText: context.tr('restaurants_booking_note_hint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_r.bookingNote.trim().isNotEmpty)
              Container(
                key: const ValueKey('booking-cafe-note'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('restaurants_booking_from_cafe'), style: TextStyle(fontSize: 11, color: c.ink2)),
                    const SizedBox(height: 2),
                    Text(_r.bookingNote.trim(), style: TextStyle(fontSize: 13, color: c.ink)),
                  ],
                ),
              ),
            if (problem != null || _serverError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _serverError ?? _problemText(context, problem!),
                  key: const ValueKey('booking-error'),
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(context.tr('restaurants_booking_how'), key: const ValueKey('booking-how'), style: TextStyle(fontSize: 12, color: c.ink2)),
              ),
            FilledButton(
              key: const ValueKey('booking-submit'),
              onPressed: _busy || problem != null ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('restaurants_booking_submit')),
            ),
          ],
        ),
      ),
    );
  }
}
