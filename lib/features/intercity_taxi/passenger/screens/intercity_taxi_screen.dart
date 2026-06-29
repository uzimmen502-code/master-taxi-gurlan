import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/l10n/locale_notifier.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../shared/widgets/become_driver_button.dart';
import '../../../../models/intercity_ride.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/intercity_rides_repository.dart';
import '../../../../shared/widgets/driver_car_info_dialog.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../utils/intercity_places.dart';
import '../../../../utils/locale_utils.dart';
import '../../../../shared/navigation/ensure_car_info_via_profile.dart';
import '../../../../shared/widgets/driver_route_application_dialog.dart';
import '../../../../shared/widgets/driver_application_feedback.dart';
import '../controllers/intercity_taxi_controller.dart';
import '../controllers/me_and_passengers_controller.dart';
import '../services/intercity_place_history.dart';
import '../widgets/intercity_place_field.dart';
import '../widgets/intercity_ride_card.dart';
import '../widgets/intercity_pickup_sheet.dart';
import '../widgets/me_and_passengers_panel.dart';
import '../../driver/intercity_driver_resume.dart';
import '../../driver/screens/intercity_driver_panel_screen.dart';

class IntercityColors {
  static const Color primary = AppColors.primary;
  static const Color dark = AppColors.primaryDark;
  static const Color light = AppColors.scaffoldGradientEnd;
  static const Color accent = AppColors.primaryMid;
  static const Color bg = AppColors.scaffold;
  static const Color green = AppColors.primaryMid;
  static const Color red = Color(0xFFE53935);
  static const Color gold = Color(0xFFFFB300);
  static const Color text = AppColors.primaryDark;
}

class IntercityTaxiScreen extends StatelessWidget {
  final String? autoFrom;
  final String? autoTo;
  final String? openPickupForBookingId;

  const IntercityTaxiScreen({
    super.key,
    this.autoFrom,
    this.autoTo,
    this.openPickupForBookingId,
  });

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
          create: (_) => MeAndPassengersController(
            repo: IntercityBookingsRepository(),
            userPhone: '',
          ),
        ),
      ],
      child: _IntercityTaxiView(
        autoFrom: autoFrom,
        autoTo: autoTo,
        openPickupForBookingId: openPickupForBookingId,
      ),
    );
  }
}

class _IntercityTaxiView extends StatefulWidget {
  const _IntercityTaxiView({
    this.autoFrom,
    this.autoTo,
    this.openPickupForBookingId,
  });

  final String? autoFrom;
  final String? autoTo;
  final String? openPickupForBookingId;

  @override
  State<_IntercityTaxiView> createState() => _IntercityTaxiViewState();
}

class _IntercityTaxiViewState extends State<_IntercityTaxiView> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  bool _bootstrapped = false;
  IntercityTaxiController? _controllerRef;
  MeAndPassengersController? _panelRef;
  bool _pickupPromptHandled = false;
  bool _isSubmitting = false;

  Timer? _debounce;
  bool _showFromSug = false;
  bool _showToSug = false;
  List<String> _fromSuggestions = const [];
  List<String> _toSuggestions = const [];
  List<String> _fromRecent = const [];
  List<String> _toRecent = const [];
  String? _lastRouteFrom;
  String? _lastRouteTo;

  void _bindControllers() {
    final c = context.read<IntercityTaxiController>();
    context.read<MeAndPassengersController>().attachPassengerReset(c.resetPassengers);

    if (_controllerRef != c) {
      _controllerRef?.removeListener(_applyControllerToTextFields);
      _controllerRef?.removeListener(_handleError);
      _controllerRef = c;
      _controllerRef!.addListener(_applyControllerToTextFields);
      _controllerRef!.addListener(_handleError);
    }
  }

  Locale get _currentLocale => Localizations.localeOf(context);

  @override
  void initState() {
    super.initState();
    _fromCtrl.addListener(_syncFromController);
    _toCtrl.addListener(_syncToController);
    _fromFocus.addListener(_onFromFocusChanged);
    _toFocus.addListener(_onToFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final panelCtrl = context.read<MeAndPassengersController>();
      _panelRef = panelCtrl;
      panelCtrl.addListener(_onPanelUpdate);
      await panelCtrl.loadIfActive();
      if (!mounted) return;
      _schedulePickupPrompt(panelCtrl);
      if (!panelCtrl.hasActiveBooking) {
        await _loadLastSearch();
        await _loadPlaceHistory();
        if (!mounted) return;
      }
      if (widget.autoFrom != null && widget.autoTo != null) {
        await _autoSearch(
          widget.autoFrom!,
          widget.autoTo!,
        );
      }
    });
  }

  void _schedulePickupPrompt(MeAndPassengersController panelCtrl) {
    final bookingId = widget.openPickupForBookingId?.trim();
    if (bookingId == null || bookingId.isEmpty) return;
    panelCtrl.requestPickupPrompt(bookingId);
    _onPanelUpdate();
  }

  void _onPanelUpdate() {
    if (!mounted || _pickupPromptHandled) return;
    final panelCtrl = _panelRef;
    if (panelCtrl == null || !panelCtrl.shouldOpenPickupSheet) return;
    _pickupPromptHandled = true;
    panelCtrl.consumePickupPrompt();
    final booking = panelCtrl.myBooking;
    if (booking == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      IntercityPickupSheet.show(context, booking: booking);
    });
  }

  Future<void> _autoSearch(String from, String to) async {
    if (!mounted) return;
    final c = context.read<IntercityTaxiController>();

    _fromCtrl.text = IntercityPlaces.displayForLocale(from, _currentLocale);
    _toCtrl.text = IntercityPlaces.displayForLocale(to, _currentLocale);
    c.selectFrom(from);
    c.selectTo(to);

    await _saveLastSearch(from, to);
    await IntercityPlaceHistory.addFrom(from);
    await IntercityPlaceHistory.addTo(to);

    if (!mounted) return;
    context.read<MeAndPassengersController>().collapseForSearch();
    await c.search();
  }

  Future<void> _saveLastSearch(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_intercity_from', from);
    await prefs.setString('last_intercity_to', to);
    if (!mounted) return;
    setState(() {
      _lastRouteFrom = from;
      _lastRouteTo = to;
    });
  }

  Future<void> _loadLastSearch() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final from = prefs.getString('last_intercity_from') ?? '';
    final to = prefs.getString('last_intercity_to') ?? '';
    setState(() {
      _lastRouteFrom = from.isNotEmpty ? from : null;
      _lastRouteTo = to.isNotEmpty ? to : null;
    });
    if (from.isNotEmpty) {
      _fromCtrl.text = IntercityPlaces.displayForLocale(from, _currentLocale);
      context.read<IntercityTaxiController>().selectFrom(from);
    }
    if (to.isNotEmpty) {
      _toCtrl.text = IntercityPlaces.displayForLocale(to, _currentLocale);
      context.read<IntercityTaxiController>().selectTo(to);
    }
  }

  Future<void> _loadPlaceHistory() async {
    final from = await IntercityPlaceHistory.loadFrom();
    final to = await IntercityPlaceHistory.loadTo();
    if (!mounted) return;
    setState(() {
      _fromRecent = from;
      _toRecent = to;
    });
  }

  void _hideAllSuggestions() {
    setState(() {
      _showFromSug = false;
      _showToSug = false;
      _fromSuggestions = const [];
      _toSuggestions = const [];
    });
  }

  void _onFromFocusChanged() {
    if (!mounted) return;
    if (_fromFocus.hasFocus) {
      setState(() {
        _showToSug = false;
        _showFromSug = true;
        _fromSuggestions = IntercityPlaces.mergedSuggestions(
          query: _fromCtrl.text,
          locale: _currentLocale,
          recentCanonical: _fromRecent,
        );
      });
    } else {
      setState(() => _showFromSug = false);
    }
  }

  void _onToFocusChanged() {
    if (!mounted) return;
    if (_toFocus.hasFocus) {
      setState(() {
        _showFromSug = false;
        _showToSug = true;
        _toSuggestions = IntercityPlaces.mergedSuggestions(
          query: _toCtrl.text,
          locale: _currentLocale,
          recentCanonical: _toRecent,
        );
      });
    } else {
      setState(() => _showToSug = false);
    }
  }

  void _onFromQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _fromSuggestions = IntercityPlaces.mergedSuggestions(
          query: _fromCtrl.text,
          locale: _currentLocale,
          recentCanonical: _fromRecent,
        );
        _showFromSug = true;
      });
    });
  }

  void _onToQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _toSuggestions = IntercityPlaces.mergedSuggestions(
          query: _toCtrl.text,
          locale: _currentLocale,
          recentCanonical: _toRecent,
        );
        _showToSug = true;
      });
    });
  }

  Future<void> _applyFromSelection(
    String displayLabel, {
    bool saveHistory = true,
  }) async {
    final canonical = IntercityPlaces.normalizeLocation(displayLabel);
    if (!mounted) return;
    final c = context.read<IntercityTaxiController>();
    _fromCtrl.text = IntercityPlaces.displayForLocale(canonical, _currentLocale);
    c.selectFrom(canonical);
    if (saveHistory) {
      await IntercityPlaceHistory.addFrom(canonical);
      _fromRecent = await IntercityPlaceHistory.loadFrom();
    }
    setState(() {
      _showFromSug = false;
      _fromSuggestions = const [];
    });
    _fromFocus.unfocus();
  }

  Future<void> _applyToSelection(
    String displayLabel, {
    bool saveHistory = true,
  }) async {
    final canonical = IntercityPlaces.normalizeLocation(displayLabel);
    if (!mounted) return;
    final c = context.read<IntercityTaxiController>();
    _toCtrl.text = IntercityPlaces.displayForLocale(canonical, _currentLocale);
    c.selectTo(canonical);
    if (saveHistory) {
      await IntercityPlaceHistory.addTo(canonical);
      _toRecent = await IntercityPlaceHistory.loadTo();
    }
    setState(() {
      _showToSug = false;
      _toSuggestions = const [];
    });
    _toFocus.unfocus();
  }

  Future<void> _applyLastRouteChip() async {
    final from = _lastRouteFrom;
    final to = _lastRouteTo;
    if (from == null || to == null) return;
    await _applyFromSelection(
      IntercityPlaces.displayForLocale(from, _currentLocale),
      saveHistory: false,
    );
    if (!mounted) return;
    await _applyToSelection(
      IntercityPlaces.displayForLocale(to, _currentLocale),
      saveHistory: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindControllers();
    if (_bootstrapped) return;
    _bootstrapped = true;
  }

  bool _commitRouteFromFields(IntercityTaxiController c) {
    return c.commitRouteFromText(
      fromText: _fromCtrl.text,
      toText: _toCtrl.text,
    );
  }

  /// Controllerda swap/select bo'lganda matn maydonlarini sync qilish.
  void _applyControllerToTextFields() {
    if (!mounted) return;
    final c = _controllerRef!;
    final locale = Localizations.localeOf(context);

    if (c.selectedFromLocation != null) {
      final fromDisp =
          IntercityPlaces.displayForLocale(c.selectedFromLocation!, locale);
      if (_fromCtrl.text != fromDisp) {
        _fromCtrl.text = fromDisp;
      }
    }
    if (c.selectedToLocation != null) {
      final toDisp =
          IntercityPlaces.displayForLocale(c.selectedToLocation!, locale);
      if (_toCtrl.text != toDisp) {
        _toCtrl.text = toDisp;
      }
    }
  }

  void _syncFromController() {
    if (!mounted) return;
    if (_fromCtrl.text.trim().isEmpty) {
      context.read<IntercityTaxiController>().selectFrom('');
    }
  }

  void _syncToController() {
    if (!mounted) return;
    if (_toCtrl.text.trim().isEmpty) {
      context.read<IntercityTaxiController>().selectTo('');
    }
  }

  void _handleError() {
    if (!mounted) return;
    final err = _controllerRef!.errorMessage;
    if (err == null) return;
    final isNoDriver =
        err == 'no_driver_today' || err == 'no_driver_tomorrow';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isNoDriver ? Icons.info_outline : Icons.warning_amber,
          color: isNoDriver ? IntercityColors.primary : Colors.white,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.trMsg(err),
            style: TextStyle(
              color: isNoDriver ? IntercityColors.text : Colors.white,
            ),
          ),
        ),
      ]),
      backgroundColor:
          isNoDriver ? AppColors.cardGradientEnd : IntercityColors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    _controllerRef!.clearError();
  }

  Future<bool> _ensureLanguageSelected() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('saved_language')) return true;
    if (!mounted) return false;

    final chosen = await showModalBottomSheet<Locale>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                context.tr('language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              title: Text(context.tr('lang_uz_cyrl')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.uzCyrl),
            ),
            ListTile(
              title: Text(context.tr('lang_uz_latn')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.uzLatn),
            ),
            ListTile(
              title: Text(context.tr('lang_ru')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.ru),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return false;
    await context.read<LocaleNotifier>().setLocale(chosen);
    return true;
  }

  Future<void> _onSearchTap() async {
    if (!await _ensureLanguageSelected()) return;
    if (!mounted) return;
    final c = context.read<IntercityTaxiController>();
    if (c.isLoading || c.isSearching) return;
    _commitRouteFromFields(c);
    final from = c.selectedFromLocation ?? '';
    final to = c.selectedToLocation ?? '';
    if (from.isNotEmpty && to.isNotEmpty) {
      await _saveLastSearch(from, to);
      await IntercityPlaceHistory.addFrom(from);
      await IntercityPlaceHistory.addTo(to);
      if (mounted) {
        final recentFrom = await IntercityPlaceHistory.loadFrom();
        final recentTo = await IntercityPlaceHistory.loadTo();
        if (!mounted) return;
        setState(() {
          _fromRecent = recentFrom;
          _toRecent = recentTo;
        });
      }
    }
    _hideAllSuggestions();
    if (!mounted) return;
    context.read<MeAndPassengersController>().collapseForSearch();
    await c.search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _panelRef?.removeListener(_onPanelUpdate);
    _controllerRef?.removeListener(_applyControllerToTextFields);
    _controllerRef?.removeListener(_handleError);
    _fromCtrl.removeListener(_syncFromController);
    _toCtrl.removeListener(_syncToController);
    _fromFocus.removeListener(_onFromFocusChanged);
    _toFocus.removeListener(_onToFocusChanged);
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  Future<void> _onIntercityDriverTap() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();
    try {
      await _runIntercityDriverTap();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _runIntercityDriverTap() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);
    if (!mounted) return;

    if (uid.length < 9) {
      _showSnack(
        context.tr('fill_phone_in_profile'),
        Colors.orange.shade700,
      );
      return;
    }

    if (!await ensureCarInfoViaProfile(context)) return;
    if (!mounted) return;

    final driverRepo = context.read<DriverRepository>();
    final approved = await driverRepo.isApprovedForTaxi(
      uid: uid,
      taxiType: 'intercity',
    );
    if (!mounted) return;

    if (approved) {
      if (await IntercityDriverResume.openPanelIfActive(context, driverId: uid)) {
        return;
      }
      if (!mounted) return;
      final started = await showDriverCarInfoDialog(
        context: context,
        taxiType: 'intercity',
        primaryColor: IntercityColors.primary,
      );
      if (!mounted || !started) return;
      final args = await IntercityDriverResume.loadPanelArgs(uid);
      if (args == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IntercityDriverPanelScreen(
            driverId: args.driverId,
            driverName: args.driverName,
            driverPhone: args.driverPhone,
            driverCar: args.driverCar,
            driverPlate: args.driverPlate,
          ),
        ),
      );
      return;
    }

    final result = await showDriverRouteApplicationDialog(
      context,
      taxiType: 'intercity',
    );
    if (result == null || !mounted) return;

    final carUid = canonicalPhoneId(uid);
    final carFromProfile = await UserRepository().getCarInfo(carUid);
    if (carFromProfile == null || !mounted) return;
    final carModel = carFromProfile['carModel'] ?? '';
    final carColor = carFromProfile['carColor'] ?? '';
    final carPlate = carFromProfile['carPlate'] ?? '';
    await prefs.setString('car_model', carModel);
    await prefs.setString('car_color', carColor);
    await prefs.setString('car_plate', carPlate);
    final carSeats = int.tryParse(carFromProfile['carSeats'] ?? '') ?? 0;
    if (carSeats > 0) await prefs.setInt('car_seats', carSeats);

    final name = prefs.getString('user_name') ?? '';
    final car =
        '$carModel${carColor.isEmpty ? '' : ' В· $carColor'}';

    try {
      final submitResult = await driverRepo.submitDriverApplication(
        uid: uid,
        name: name,
        phone: phone,
        car: car,
        plate: carPlate,
        taxiType: 'intercity',
        routeFrom: result.from,
        routeTo: result.to,
        routeStops: result.midStops,
      );
      if (!mounted) return;
      if (submitResult.autoApproved) {
        await prefs.setString('user_role', 'driver');
        if (!mounted) return;
        _showSnack(
          context.tr('intercity_driver_mode_activated'),
          AppColors.primaryDark,
        );
      } else {
        await showDriverApplicationPendingFeedback(
          context,
          result: submitResult,
          resentMessageKey: 'intercity_driver_request_sent',
          snackColor: Colors.orange.shade700,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        context.tr('driver_mode_error').replaceAll('{error}', '$e'),
        IntercityColors.red,
      );
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(message),
    ));
  }

  void _callDriver(String phone) {
    callPhone(phone);
  }

  double _panelBottomPadding(
    BuildContext context,
    MeAndPassengersController panelCtrl, {
    double whenHidden = 24,
  }) {
    if (!panelCtrl.isPanelVisible) return whenHidden;
    return MediaQuery.of(context).size.height * panelCtrl.sheetExtent + 12;
  }

  void _bookRide(IntercityRide ride) {
    final taxiCtrl = context.read<IntercityTaxiController>();
    taxiCtrl.resetPassengersForRide(ride.availableSeats);
    context.read<MeAndPassengersController>().showPassengerPick(ride);
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(context.tr('intercity_taxi'),
                  style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                BecomeDriverButton(
                  onTap: _onIntercityDriverTap,
                  loading: _isSubmitting,
                  color: IntercityColors.primary,
                ),
              ],
            ),
      body: Stack(
        children: [
          c.hasSearched
              ? _buildResultsView(c)
              : _buildSearchForm(c, today, tomorrow),
          const Positioned.fill(
            child: MeAndPassengersPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView(IntercityTaxiController c) {
    final panelCtrl = context.watch<MeAndPassengersController>();
    return Column(
      children: [
        Container(
          color: AppColors.courierGreen,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 12,
            left: 16,
            right: 16,
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  c.resetSearch();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.selectedFromLocation ?? ''}'
                      ' в†’ '
                      '${c.selectedToLocation ?? ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      c.isSearching
                          ? 'ТљРёРґРёСЂРёР»РјРѕТ›РґР°...'
                          : '${c.rides.length} С‚Р° СЂРµР№СЃ С‚РѕРїРёР»РґРё',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: c.isSearching
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.courierGreen,
                  ),
                )
              : c.rides.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_bus_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Р РµР№СЃ С‚РѕРїРёР»РјР°РґРё',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: c.resetSearch,
                            icon: const Icon(Icons.refresh),
                            label: const Text('ТљР°Р№С‚Р° Т›РёРґРёСЂРёС€'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        12,
                        14,
                        _panelBottomPadding(context, panelCtrl),
                      ),
                      itemCount: c.rides.length,
                      itemBuilder: (_, i) => IntercityRideCard(
                        ride: c.rides[i],
                        onCall: () => _callDriver(c.rides[i].phoneNumber),
                        onBook: () => _bookRide(c.rides[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  // в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ Search form в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

  Widget _buildSearchForm(
      IntercityTaxiController c, DateTime today, DateTime tomorrow) {
    final panelCtrl = context.watch<MeAndPassengersController>();
    final locale = _currentLocale;
    final showLastRouteChip = _lastRouteFrom != null &&
        _lastRouteTo != null &&
        _lastRouteFrom!.isNotEmpty &&
        _lastRouteTo!.isNotEmpty;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _hideAllSuggestions();
      },
      child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + _panelBottomPadding(context, panelCtrl, whenHidden: 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLastRouteChip) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: Icon(Icons.history, size: 16, color: Colors.grey.shade700),
                label: Text(
                  '${IntercityPlaces.displayForLocale(_lastRouteFrom!, locale)}'
                  ' в†’ '
                  '${IntercityPlaces.displayForLocale(_lastRouteTo!, locale)}',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: _applyLastRouteChip,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _RouteCard(
            locale: locale,
            fromCtrl: _fromCtrl,
            toCtrl: _toCtrl,
            fromFocus: _fromFocus,
            toFocus: _toFocus,
            showFromSuggestions: _showFromSug,
            showToSuggestions: _showToSug,
            fromSuggestions: _fromSuggestions,
            toSuggestions: _toSuggestions,
            fromRecent: _fromRecent,
            toRecent: _toRecent,
            fromHint: context.tr('from'),
            toHint: context.tr('to'),
            onFromChanged: _onFromQueryChanged,
            onToChanged: _onToQueryChanged,
            onFromSelected: (v) => _applyFromSelection(v),
            onToSelected: (v) => _applyToSelection(v),
            onFromTap: () {
              setState(() {
                _showToSug = false;
                _showFromSug = true;
                _fromSuggestions = IntercityPlaces.mergedSuggestions(
                  query: _fromCtrl.text,
                  locale: locale,
                  recentCanonical: _fromRecent,
                );
              });
            },
            onToTap: () {
              setState(() {
                _showFromSug = false;
                _showToSug = true;
                _toSuggestions = IntercityPlaces.mergedSuggestions(
                  query: _toCtrl.text,
                  locale: locale,
                  recentCanonical: _toRecent,
                );
              });
            },
            onSwap: () {
              _hideAllSuggestions();
              final tmp = _fromCtrl.text;
              _fromCtrl.text = _toCtrl.text;
              _toCtrl.text = tmp;
              c.swap();
            },
            onClearFrom: () {
              _fromCtrl.clear();
              c.clearFrom();
              setState(() => _fromSuggestions = const []);
            },
            onClearTo: () {
              _toCtrl.clear();
              c.clearTo();
              setState(() => _toSuggestions = const []);
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _dateCard(
                    context.tr('today'),
                    formatPickDateLabel(
                      today,
                      yearSuffix:
                          _currentLocale.languageCode == 'ru' ? ' Рі.' : ' y',
                    ),
                    c.isToday,
                    () => c.setIsToday(true))),
            const SizedBox(width: 12),
            Expanded(
                child: _dateCard(
                    context.tr('tomorrow'),
                    formatPickDateLabel(
                      tomorrow,
                      yearSuffix:
                          _currentLocale.languageCode == 'ru' ? ' Рі.' : ' y',
                    ),
                    !c.isToday,
                    () => c.setIsToday(false))),
          ]),
          const SizedBox(height: 24),
          _SearchButton(
            isLoading: c.isLoading,
            onTap: c.isLoading ? null : _onSearchTap,
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }

  Widget _dateCard(String title, String date, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 7),
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
                      color: IntercityColors.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
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
                          color: sel ? Colors.white : IntercityColors.text)),
                  Text(date,
                      style: TextStyle(
                          fontSize: 11,
                          color: sel ? Colors.white70 : Colors.grey.shade500)),
                ]),
          ],
        ),
      ),
    );
  }

}

// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Inline widgets
// в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.locale,
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromFocus,
    required this.toFocus,
    required this.showFromSuggestions,
    required this.showToSuggestions,
    required this.fromSuggestions,
    required this.toSuggestions,
    required this.fromRecent,
    required this.toRecent,
    required this.fromHint,
    required this.toHint,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onFromSelected,
    required this.onToSelected,
    required this.onFromTap,
    required this.onToTap,
    required this.onSwap,
    required this.onClearFrom,
    required this.onClearTo,
  });

  final Locale locale;
  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final bool showFromSuggestions;
  final bool showToSuggestions;
  final List<String> fromSuggestions;
  final List<String> toSuggestions;
  final List<String> fromRecent;
  final List<String> toRecent;
  final String fromHint;
  final String toHint;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final ValueChanged<String> onFromSelected;
  final ValueChanged<String> onToSelected;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
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
              color: IntercityColors.primary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          IntercityPlaceField(
            controller: fromCtrl,
            focusNode: fromFocus,
            hint: fromHint,
            dotColor: IntercityColors.green,
            showSuggestions: showFromSuggestions,
            suggestions: fromSuggestions,
            recentCanonical: fromRecent,
            locale: locale,
            onChanged: onFromChanged,
            onSelected: onFromSelected,
            onClear: onClearFrom,
            onTap: onFromTap,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Container(width: 2, height: 22, color: Colors.grey.shade200),
                const Spacer(),
                GestureDetector(
                  onTap: onSwap,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: IntercityColors.light,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.swap_vert,
                      color: IntercityColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IntercityPlaceField(
            controller: toCtrl,
            focusNode: toFocus,
            hint: toHint,
            dotColor: IntercityColors.red,
            showSuggestions: showToSuggestions,
            suggestions: toSuggestions,
            recentCanonical: toRecent,
            locale: locale,
            onChanged: onToChanged,
            onSelected: onToSelected,
            onClear: onClearTo,
            onTap: onToTap,
          ),
        ],
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
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [IntercityColors.dark, IntercityColors.accent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: IntercityColors.primary.withValues(alpha: 0.35),
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
              : const Icon(Icons.search, size: 20),
          label: Text(context.tr('intercity_search'),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}
