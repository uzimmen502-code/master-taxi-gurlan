import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/intercity_ride.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart';
import '../../../../shared/widgets/driver_car_info_dialog.dart';
import '../../../../utils/intercity_places.dart';
import '../controllers/intercity_taxi_controller.dart';
import '../controllers/my_bookings_controller.dart';
import '../widgets/booking_confirmation_sheet.dart';
import '../widgets/my_bookings_section.dart';
import '../widgets/ride_card.dart';

class IntercityColors {
  static const Color primary = Color(0xFF7B1FA2);
  static const Color dark = Color(0xFF9C27B0);
  static const Color light = Color(0xFFF3E5F5);
  static const Color accent = Color(0xFF9C27B0);
  static const Color bg = Color(0xFFF3E5F5);
  static const Color green = Color(0xFF43A047);
  static const Color red = Color(0xFFE53935);
  static const Color gold = Color(0xFFFFB300);
  static const Color text = Color(0xFF1A1A2E);
}

class IntercityTaxiScreen extends StatelessWidget {
  const IntercityTaxiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (ctx) => IntercityTaxiController(
            ridesRepo: ctx.read<IntercityRidesRepository>(),
            bookingsRepo: ctx.read<IntercityBookingsRepository>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => MyBookingsController(
            bookingsRepo: ctx.read<IntercityBookingsRepository>(),
          )..load(),
        ),
      ],
      child: const _IntercityTaxiView(),
    );
  }
}

class _IntercityTaxiView extends StatefulWidget {
  const _IntercityTaxiView();

  @override
  State<_IntercityTaxiView> createState() => _IntercityTaxiViewState();
}

class _IntercityTaxiViewState extends State<_IntercityTaxiView> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  List<String> _fromSug = const [];
  List<String> _toSug = const [];
  bool _showFromSug = false;
  bool _showToSug = false;

  bool _bootstrapped = false;
  IntercityTaxiController? _controllerRef;

  @override
  void initState() {
    super.initState();
    _fromCtrl.addListener(_onFromChanged);
    _toCtrl.addListener(_onToChanged);
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) {
        setState(() => _showFromSug = false);
      }
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) {
        setState(() => _showToSug = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _controllerRef = context.read<IntercityTaxiController>();
    _controllerRef!.addListener(_syncFromController);
    _controllerRef!.addListener(_handleError);
  }

  /// Controllerda swap/select bo'lganda matn maydonlarini sync qilish.
  void _syncFromController() {
    if (!mounted) return;
    final c = _controllerRef!;
    final from = c.selectedFromLocation ?? '';
    final to = c.selectedToLocation ?? '';
    if (_fromCtrl.text != from) {
      _fromCtrl.text = from;
    }
    if (_toCtrl.text != to) {
      _toCtrl.text = to;
    }
  }

  void _handleError() {
    if (!mounted) return;
    final err = _controllerRef!.errorMessage;
    if (err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(err)),
      ]),
      backgroundColor: IntercityColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    _controllerRef!.clearError();
  }

  void _onFromChanged() {
    final q = _fromCtrl.text;
    setState(() {
      _fromSug = IntercityPlaces.search(q);
      _showFromSug = _fromSug.isNotEmpty;
    });
  }

  void _onToChanged() {
    final q = _toCtrl.text;
    setState(() {
      _toSug = IntercityPlaces.search(q);
      _showToSug = _toSug.isNotEmpty;
    });
  }

  void _selectFrom(String loc) {
    final c = context.read<IntercityTaxiController>();
    _fromCtrl.text = loc;
    c.selectFrom(loc);
    setState(() => _showFromSug = false);
    _fromFocus.unfocus();
  }

  void _selectTo(String loc) {
    final c = context.read<IntercityTaxiController>();
    _toCtrl.text = loc;
    c.selectTo(loc);
    setState(() => _showToSug = false);
    _toFocus.unfocus();
    if (loc == 'Тошкент ш.') _showDistrictPicker();
  }

  @override
  void dispose() {
    _controllerRef?.removeListener(_syncFromController);
    _controllerRef?.removeListener(_handleError);
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _showDistrictPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Тошкент туманини танланг',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: IntercityPlaces.tashkentDistricts.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.location_city,
                      color: IntercityColors.primary, size: 20),
                  title: Text(IntercityPlaces.tashkentDistricts[i]),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: IntercityColors.primary),
                  onTap: () {
                    final d = IntercityPlaces.tashkentDistricts[i];
                    context.read<IntercityTaxiController>().setDistrict(d);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    final url = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  /// Реал бронь flow:
  ///   1. Тасдиқлаш sheet → controller `bookRide()` ни чақиради (transactional).
  ///   2. Муваффақиятли бўлса — success sheet кўрсатилади, controller'da
  ///      `lastBooking` тозалади.
  ///   3. Хато бўлса — `_handleError` listener Snackbar кўрсатади.
  Future<void> _bookRide(IntercityRide ride) async {
    final controller = context.read<IntercityTaxiController>();
    final booking = await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: controller,
        child: BookingConfirmationSheet(
          ride: ride,
          primaryColor: IntercityColors.primary,
          greenColor: IntercityColors.green,
          redColor: IntercityColors.red,
        ),
      ),
    );

    if (!mounted) return;
    if (booking == null) {
      controller.clearLoyalty();
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BookingSuccessSheet(
        booking: booking,
        primaryColor: IntercityColors.primary,
        greenColor: IntercityColors.green,
        onCall: () {
          Navigator.pop(ctx);
          _callDriver(booking.driverPhone);
        },
      ),
    );

    if (!mounted) return;
    controller
      ..clearLastBooking()
      ..clearLoyalty();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<IntercityTaxiController>();
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    return Scaffold(
      backgroundColor: IntercityColors.bg,
      appBar: c.hasSearched
          ? null
          : AppBar(
              backgroundColor: IntercityColors.dark,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Шаҳарлараро такси',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                _DriverButton(
                  onTap: () => showDriverCarInfoDialog(
                    context: context,
                    taxiType: 'intercity',
                    primaryColor: IntercityColors.primary,
                  ),
                ),
              ],
            ),
      body: c.hasSearched
          ? _buildResultsView(c)
          : _buildSearchForm(c, today, tomorrow),
    );
  }

  // ───────────────────── Search form ─────────────────────

  Widget _buildSearchForm(
      IntercityTaxiController c, DateTime today, DateTime tomorrow) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  IntercityColors.dark,
                  IntercityColors.primary,
                  IntercityColors.accent
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    const Icon(Icons.route, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Шаҳарлараро такси',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ]),
          ),
          const MyBookingsSection(primaryColor: IntercityColors.primary),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteCard(
                  fromCtrl: _fromCtrl,
                  toCtrl: _toCtrl,
                  fromFocus: _fromFocus,
                  toFocus: _toFocus,
                  onSwap: () {
                    final tmp = _fromCtrl.text;
                    _fromCtrl.text = _toCtrl.text;
                    _toCtrl.text = tmp;
                    c.swap();
                  },
                  onClearFrom: () {
                    _fromCtrl.clear();
                    c.clearFrom();
                    setState(() {
                      _fromSug = const [];
                      _showFromSug = false;
                    });
                  },
                  onClearTo: () {
                    _toCtrl.clear();
                    c.clearTo();
                    setState(() {
                      _toSug = const [];
                      _showToSug = false;
                    });
                  },
                ),
                if (_showFromSug && _fromSug.isNotEmpty)
                  _suggestionsList(_fromSug, _selectFrom),
                if (_showToSug && _toSug.isNotEmpty)
                  _suggestionsList(_toSug, _selectTo),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _dateCard(
                          'БУГУН',
                          '${today.day}.${today.month.toString().padLeft(2, "0")}',
                          c.isToday,
                          () => c.setIsToday(true))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _dateCard(
                          'ЭРТАГА',
                          '${tomorrow.day}.${tomorrow.month.toString().padLeft(2, "0")}',
                          !c.isToday,
                          () => c.setIsToday(false))),
                ]),
                const SizedBox(height: 16),
                _PassengerCounter(
                  passengers: c.passengers,
                  onDec: c.decPassengers,
                  onInc: c.incPassengers,
                ),
                const SizedBox(height: 24),
                _SearchButton(
                  isLoading: c.isLoading,
                  onTap: c.isLoading ? null : c.search,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsList(List<String> list, ValueChanged<String> onTap) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: list.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (_, i) => ListTile(
          leading: const Icon(Icons.location_on,
              color: IntercityColors.primary, size: 18),
          title: Text(list[i], style: const TextStyle(fontSize: 14)),
          dense: true,
          onTap: () => onTap(list[i]),
        ),
      ),
    );
  }

  Widget _dateCard(
      String title, String date, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          gradient: sel
              ? const LinearGradient(
                  colors: [IntercityColors.dark, IntercityColors.primary])
              : null,
          color: sel ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: IntercityColors.primary.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 6)
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sel ? Icons.calendar_today : Icons.calendar_today_outlined,
              size: 14,
              color: sel ? Colors.white : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              sel ? Colors.white : IntercityColors.text)),
                  Text(date,
                      style: TextStyle(
                          fontSize: 11,
                          color: sel
                              ? Colors.white70
                              : Colors.grey.shade500)),
                ]),
          ],
        ),
      ),
    );
  }

  // ───────────────────── Results view ─────────────────────

  Widget _buildResultsView(IntercityTaxiController c) {
    return Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [IntercityColors.dark, IntercityColors.primary]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              GestureDetector(
                onTap: c.resetSearch,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.circle,
                            color: Colors.greenAccent, size: 8),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              IntercityPlaces.extractCity(
                                  c.selectedFromLocation ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward,
                                color: Colors.white70, size: 14)),
                        const Icon(Icons.location_on,
                            color: Colors.redAccent, size: 10),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                              IntercityPlaces.extractCity(
                                  c.selectedToLocation ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text('${c.rides.length} та рейс топилди',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12)),
                    ]),
              ),
              _DriverButton(
                onTap: () => showDriverCarInfoDialog(
                  context: context,
                  taxiType: 'intercity',
                  primaryColor: IntercityColors.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: c.rides.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.search_off,
                          size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('Рейслар топилмади',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: c.resetSearch,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Қайта қидириш'),
                      ),
                    ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                  itemCount: c.rides.length,
                  itemBuilder: (_, i) => IntercityRideCard(
                    ride: c.rides[i],
                    number: i + 1,
                    primaryColor: IntercityColors.primary,
                    lightColor: IntercityColors.light,
                    redColor: IntercityColors.red,
                    greenColor: IntercityColors.green,
                    goldColor: IntercityColors.gold,
                    textColor: IntercityColors.text,
                    onCall: () => _callDriver(c.rides[i].phoneNumber),
                    onBook: () => _bookRide(c.rides[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Inline widgets
// ─────────────────────────────────────────────────────────────────────

class _DriverButton extends StatelessWidget {
  const _DriverButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Ҳайдовчи',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: IntercityColors.primary)),
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromFocus,
    required this.toFocus,
    required this.onSwap,
    required this.onClearFrom,
    required this.onClearTo,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final VoidCallback onSwap;
  final VoidCallback onClearFrom;
  final VoidCallback onClearTo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: IntercityColors.primary.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: IntercityColors.green, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
            controller: fromCtrl,
            focusNode: fromFocus,
            decoration: InputDecoration(
              hintText: 'Қаердан?',
              hintStyle:
                  TextStyle(color: Colors.grey.shade400, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              suffixIcon: fromCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear,
                          size: 18, color: Colors.grey.shade400),
                      onPressed: onClearFrom)
                  : null,
            ),
          )),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            const SizedBox(width: 4),
            Container(width: 2, height: 24, color: Colors.grey.shade200),
            const Spacer(),
            GestureDetector(
              onTap: onSwap,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: IntercityColors.light,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_vert,
                    color: IntercityColors.primary, size: 20),
              ),
            ),
          ]),
        ),
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: IntercityColors.red,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
            controller: toCtrl,
            focusNode: toFocus,
            decoration: InputDecoration(
              hintText: 'Қаерга?',
              hintStyle:
                  TextStyle(color: Colors.grey.shade400, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              suffixIcon: toCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear,
                          size: 18, color: Colors.grey.shade400),
                      onPressed: onClearTo)
                  : null,
            ),
          )),
        ]),
      ]),
    );
  }
}

class _PassengerCounter extends StatelessWidget {
  const _PassengerCounter({
    required this.passengers,
    required this.onDec,
    required this.onInc,
  });
  final int passengers;
  final VoidCallback onDec;
  final VoidCallback onInc;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: IntercityColors.light,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.people,
                color: IntercityColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Йўловчилар',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Spacer(),
          _counterBtn(
              Icons.remove, onDec, Colors.grey.shade100, Colors.grey.shade600),
          const SizedBox(width: 12),
          Text('$passengers',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: IntercityColors.primary)),
          const SizedBox(width: 12),
          _counterBtn(Icons.add, onInc, IntercityColors.primary, Colors.white),
        ],
      ),
    );
  }

  Widget _counterBtn(
      IconData icon, VoidCallback onTap, Color bg, Color iconColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.isLoading, required this.onTap});
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [IntercityColors.dark, IntercityColors.accent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: IntercityColors.primary.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.search, size: 22),
          label: const Text('РЕЙСЛАРНИ ҚИДИРИШ',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}
