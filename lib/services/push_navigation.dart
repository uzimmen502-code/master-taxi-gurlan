import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/service_config_holder.dart';
import '../core/utils/formatters.dart';
import '../features/home/home_module_gate.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/courier/screens/courier_screen.dart';
import '../features/customer_confirm/customer_confirm_controller.dart';
import '../features/customer_confirm/screens/customer_confirm_screen.dart';
import '../features/restaurants/courier/restaurant_nearby_orders_screen.dart';
import '../features/restaurants/merchant/restaurant_panel_screen.dart';
import '../features/intercity_taxi/driver/intercity_driver_resume.dart';
import '../features/intercity_taxi/driver/screens/intercity_driver_panel_screen.dart';
import '../features/intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../features/relatives/screens/relatives_screen.dart';
import '../features/dating/dating_telegram_bot.dart';
import '../l10n/app_localizations.dart';
import '../features/ads/screens/my_ads_screen.dart';
import '../features/jobs/screens/jobs_screen.dart';
import '../features/local_taxi/passenger/screens/local_taxi_screen.dart';
import '../features/marshrut/driver/screens/driver_panel_marshrut_screen.dart';
import '../features/marshrut/driver/screens/driver_register_marshrut_screen.dart';
import '../features/marshrut/passenger/screens/marshrut_accepted_screen.dart';
import '../features/marshrut/passenger/screens/marshrut_taxi_screen.dart';
import '../models/active_trip.dart';
import '../repositories/marshrut_driver_repository.dart';
import '../repositories/rides_repository.dart';
import '../features/profile/screens/news_hub_screen.dart';
import '../features/china_inquiry/screens/china_inquiries_screen.dart';
import '../features/profile/screens/wallet_screen.dart';
import '../features/realty/screens/my_realty_listings_screen.dart';
import '../features/realty/screens/realty_alerts_screen.dart';
import '../features/realty/screens/realty_detail_screen.dart';
import '../repositories/realty_repository.dart';
import '../shared/widgets/driver_application_feedback.dart';
import '../features/seller/screens/seller_pos_screen.dart';
import '../features/wholesale/screens/wholesale_order_detail_screen.dart';
import '../features/yuk_intercity/screens/yuk_intercity_screen.dart';
import '../features/yuk_local/screens/yuk_local_screen.dart';
import '../features/onboarding/screens/device_transfer_approve_screen.dart';
// ТАЛАБ → ТАКЛИФ ядроси (13.4.10).
import '../features/demand_offer/data/match_repository.dart';
import '../features/demand_offer/domain/canonical_id.dart';
import '../features/demand_offer/domain/demand_enums.dart';
import '../features/demand_offer/presentation/demand_detail/demand_match_detail_screen.dart';
import '../features/demand_offer/ui_adapters/service_ui_adapter.dart';
import '../features/logistics/ui/logistics_ui_adapter.dart';
import '../main.dart';
import 'user_audience.dart';

/// FCM / local push босилганда тегишли экранга ўтиш.
class PushNavigation {
  PushNavigation._();

  static const _intercityTypes = {
    'intercity_pickup_request',
    'intercity_seats_update',
    'intercity_departure_reminder',
    'intercity_trip_completed',
    'intercity_booking_cancelled',
  };

  static String encodePayload(Map<String, String> data) => jsonEncode(data);

  static Map<String, String> decodePayload(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> dataFromMessage(RemoteMessage message) {
    return message.data.map(
      (k, v) => MapEntry(k, v?.toString() ?? ''),
    );
  }

  /// Фойдаланувчи ҳамёнига тегишли push (`screen: 'wallet'`). Молия ходимига
  /// кетадиган навбат хабари (`screen: 'news'`) бунга кирмайди.
  @visibleForTesting
  static bool opensWallet(String screen) => screen == 'wallet';

  /// Улгуржи буюртма push'и бўлса — `orderId` (Firestore ID шакли), акс ҳолда `null`.
  @visibleForTesting
  static String? wholesaleOrderIdFromPush(Map<String, String> data) {
    final type = (data['type'] ?? '').trim();
    final screen = (data['screen'] ?? '').trim();
    if (type != 'wholesale_order' && screen != 'wholesale_order') return null;
    final id = (data['orderId'] ?? '').trim();
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
  }

  static Future<void> handlePayload(String? payload) async {
    await handleData(decodePayload(payload));
  }

  static Future<void> handleData(Map<String, String> data) async {
    final nav = MyApp.navigatorKey.currentState;
    if (nav == null) return;

    final type = (data['type'] ?? '').trim();
    final screen = (data['screen'] ?? '').trim();
    final tab = (data['tab'] ?? '').trim();

    if (type == 'device_transfer_request' || screen == 'device_transfer') {
      final requestId = (data['requestId'] ?? '').trim();
      if (requestId.isEmpty) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => DeviceTransferApproveScreen(
            requestId: requestId,
            newDeviceLabel: (data['newDeviceLabel'] ?? '').trim(),
          ),
        ),
      );
      return;
    }

    // Мижоз тасдиғи (D2/D7): сервер push'и `type: customer_confirm` +
    // `module`/`id`/`step`. Push'даги қиймат ишонилмайди — экран рўйхатни
    // серверданоқ (`getCustomerPendingConfirmations`) олади.
    if (type == 'customer_confirm') {
      CustomerConfirmSignal.bump();
      await nav.push(
        MaterialPageRoute(builder: (_) => const CustomerConfirmScreen()),
      );
      return;
    }

    // ── ТАЛАБ → ТАКЛИФ ядроси (13.4.10) ──────────────────────────────
    //
    // Push юкламаси: `type: demand_match`, `demandId`, `module`, `mode`,
    // `screen: ava://demand/{id}`.
    //
    // МАХФИЙЛИК: push'да аниқ манзил ва телефон ЙЎҚ — фақат `demandId`.
    // Таклифчи экранни очганда маълумот `demand_matches` проекциясидан
    // келади (Firestore қоидаси уни фақат шу таклифчига беради).
    if (type == 'demand_match') {
      final demandId = (data['demandId'] ?? '').trim();
      if (demandId.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final uid = canonicalUserId(prefs.getString('user_phone') ?? '');
      if (uid.isEmpty) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => DemandMatchDetailScreen(
            demandId: demandId,
            providerId: uid,
            repository: MatchRepository(),
            adapters: const {
              DemandModule.service: ServiceUiAdapter(),
              DemandModule.logistics: LogisticsUiAdapter(),
            },
          ),
        ),
      );
      return;
    }

    // «Буюртма олинди» — collapse орқали эски push ўрнини олади.
    // Экран очилмайди: очиладиган нарса қолмаган.
    if (type == 'demand_taken') {
      _showPassiveSnack(nav, 'demand_error_taken');
      return;
    }

    if (type == 'intercity_passenger_gps') {
      _showPassiveSnack(nav, 'passenger_gps_received');
      return;
    }

    if (type == 'intercity_booking_pending' || type == 'intercity_booking') {
      final prefs = await SharedPreferences.getInstance();
      final uid = phoneDigits(prefs.getString('user_phone') ?? '');
      final args = uid.length >= 9
          ? await IntercityDriverResume.loadPanelArgs(uid)
          : null;
      if (args != null) {
        await nav.push(
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
      } else {
        await nav.push(
          MaterialPageRoute(builder: (_) => const IntercityTaxiScreen()),
        );
      }
      return;
    }

    if (screen == 'intercity' || _intercityTypes.contains(type)) {
      final bookingId = (data['bookingId'] ?? '').trim();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => IntercityTaxiScreen(
            openPickupForBookingId:
                type == 'intercity_pickup_request' && bookingId.isNotEmpty
                    ? bookingId
                    : null,
          ),
        ),
      );
      return;
    }

    if (type == 'marshrut_request' || type == 'marshrut_trip_incoming') {
      final tripId = (data['tripId'] ?? '').trim();
      if (tripId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_marshrut_trip_id', tripId);
      }
      final prefs = await SharedPreferences.getInstance();
      final uid = phoneDigits(prefs.getString('user_phone') ?? '');
      final profile =
          uid.isNotEmpty ? await MarshrutDriverRepository().getProfile(uid) : null;
      if (profile != null) {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => DriverPanelMarshrutScreen(
              carModel: profile.carModel,
              plate: profile.plate,
              seats: profile.seats,
              stops: profile.stops,
              driverName: profile.driverName,
              driverPhone: profile.driverPhone,
              driverId: profile.uid,
            ),
          ),
        );
      } else {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => const DriverRegisterMarshrutScreen(),
          ),
        );
      }
      return;
    }

    if (type == 'local_trip_request') {
      // Driver-targeted push; deep link saqlanmaydi — haydovchi ilovada stream orqali ko'radi.
      return;
    }

    if (type == 'local_trip_accepted') {
      final tripId = (data['tripId'] ?? '').trim();
      final prefs = await SharedPreferences.getInstance();
      if (!UserAudience.taxiDriverFrom(prefs)) {
        await prefs.setString('resume_local_trip_id', tripId);
        await nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LocalTaxiScreen()),
          (route) => route.isFirst,
        );
      }
      return;
    }

    if (type == 'marshrut_accepted') {
      final tripId = (data['tripId'] ?? '').trim();
      if (tripId.isNotEmpty) {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => FutureBuilder<ActiveTrip?>(
              future: RidesRepository().getTrip(tripId),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasData && snap.data != null) {
                  return MarshrutAcceptedScreen(trip: snap.data!);
                }
                return const MarshrutTaxiScreen();
              },
            ),
          ),
        );
      }
      return;
    }

    if (screen == 'marshrut' ||
        type == 'trip' ||
        type == 'trip_accepted') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const MarshrutTaxiScreen()),
      );
      return;
    }

    if (screen == 'my_ads' ||
        type == 'market_ad_published' ||
        type == 'market_ad_moderation') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const MyAdsScreen()),
      );
      return;
    }

    if (screen == 'jobs' ||
        type == 'ad_published' ||
        type == 'ad_moderation') {
      if (!_moduleOpen(nav, 'jobs')) return;
      await nav.push(
        MaterialPageRoute(builder: (_) => const JobsScreen()),
      );
      return;
    }

    // Кўчмас мулк: муддат огоҳлантириши. Пуллик даража тугаса объект
    // ўчади, шунинг учун хабар «Менинг объектларим»га олиб боради —
    // эга у ердан муддатни узайтиради ёки эълонни таҳрирлайди.
    // Огоҳлантирилган эълон рўйхат бошига қўйилади (`listingId`).
    // «Шундай уй чиқса, хабар бер» — push'да фақат `listingId` (манзил ва
    // рақам ЙЎҚ). Эълон ўчган бўлса — хабарномалар бўлими.
    if (screen == 'realty_match' || type == 'realty_match') {
      final listingId = (data['listingId'] ?? '').trim();
      final repo = RealtyRepository();
      final listing = await repo.fetchListing(listingId);
      if (listingId.isNotEmpty) repo.markMatchSeen(listingId);
      await nav.push(
        MaterialPageRoute(
          builder: (_) => listing == null
              ? const RealtyAlertsScreen()
              : RealtyDetailScreen(listing: listing),
        ),
      );
      return;
    }

    if (screen == 'realty_my' || type == 'realty_expiry') {
      final listingId = (data['listingId'] ?? '').trim();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => MyRealtyListingsScreen(
            highlightListingId: listingId.isEmpty ? null : listingId,
          ),
        ),
      );
      return;
    }

    // Хитой бозори: «сўровингизга таклиф келди» (functions/china_inquiries.js,
    // `screen: 'china_inquiry'`). Телефон номаълум бўлса — аввалги умумий йўл.
    if (screen == 'china_inquiry' || type == 'china_quote') {
      final prefs = await SharedPreferences.getInstance();
      final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
      if (phone.length >= 12) {
        await nav.push(
          MaterialPageRoute(builder: (_) => ChinaInquiriesScreen(phone: phone)),
        );
        return;
      }
    }

    // ── Улгуржи буюртма (functions_demand/notify/wholesale_notify.js) ──
    // `{type: 'wholesale_order', event, orderId, screen: 'wholesale_order'}` →
    // буюртма тафсилоти. Push'даги маълумотга ишонилмайди: экран ҳужжатни
    // Firestore'дан ўқийди (Rules: фақат харидор/сотувчи/админ).
    final wholesaleOrderId = wholesaleOrderIdFromPush(data);
    if (wholesaleOrderId != null) {
      final prefs = await SharedPreferences.getInstance();
      final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
      if (phone.length >= 12) {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => WholesaleOrderDetailScreen(orderId: wholesaleOrderId, viewerId: phone),
          ),
        );
        return;
      }
    }

    // ── Ҳамён (telegram_wallet_bot.js) ───────────────────────────────
    // «Ҳамён тўлдирилди / тўлдириш рад этилди / ечиш аризаси …» push'лари
    // `screen: 'wallet'` юборади, лекин аввал ҳеч қаерда ишлов берилмасди ва
    // босилганда Янгиликлар ҳабига тушарди. Энди ҳамён экрани очилади (унда
    // тўлдириш сўровларининг ҳолати ҳам кўринади). Телефон номаълум бўлса —
    // аввалги умумий йўл (ҳаб).
    if (opensWallet(screen)) {
      final prefs = await SharedPreferences.getInstance();
      final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
      if (phone.length >= 12) {
        await nav.push(
          MaterialPageRoute(builder: (_) => WalletScreen(phone: phone)),
        );
        return;
      }
    }

    // `screen == 'sell'` (эски CF payload'лари) энди алоҳида экранга
    // олиб бормайди — «Сотув маркази»га кириш йўли ёпилди. Пастдаги
    // умумий fallback уни Янгиликлар → «Хабарлар» табига олиб боради
    // (`_newsHubTabIndex`да `sell_offer` шу табга бириктирилган):
    // таклиф ҳақидаги хабарнинг ўзи ўша ерда сақланади.

    // ── Кафе-ресторан (restaurant_orders.js) ─────────────────────────
    // Ресторан а'зосига: `screen: restaurant_orders` + `restaurantId` →
    // панелнинг «Буюртмалар» таби. Курьерга таклиф
    // (`type: restaurant_courier_offer`) → курьер панели → яқиндагилар.
    if (screen == 'restaurant_orders') {
      final restaurantId = (data['restaurantId'] ?? '').trim();
      if (restaurantId.isNotEmpty) {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => RestaurantPanelScreen(restaurantId: restaurantId),
          ),
        );
        return;
      }
    }
    if (type == 'restaurant_courier_offer') {
      final prefs = await SharedPreferences.getInstance();
      final uid = canonicalUserId(prefs.getString('user_phone') ?? '');
      await nav.push(
        MaterialPageRoute(builder: (_) => const CourierScreen()),
      );
      if (uid.isNotEmpty) {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => RestaurantNearbyOrdersScreen(courierUid: uid),
          ),
        );
      }
      return;
    }

    if (screen == 'seller_pos' || type == 'seller_pickup') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const SellerPosScreen()),
      );
      return;
    }

    // Yuk push'lari hozircha faqat shaharlararo e'lon haqida. `yuk_birja` —
    // eski CF/payload'lardan keladigan screen qiymati (alias davri).
    if (type == 'yuk_listing_closed' ||
        type == 'yuk_listing_expire_soon' ||
        screen == 'yuk_intercity' ||
        screen == 'yuk_birja') {
      final listingId = (data['listingId'] ?? '').trim();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => YukIntercityScreen(
            highlightListingId: listingId.isEmpty ? null : listingId,
          ),
        ),
      );
      return;
    }

    if (screen == 'yuk_local') {
      if (!_moduleOpen(nav, 'yuk_local')) return;
      // `yuk_local_expire_soon` пуши — шу эълон детали («Узайтириш» тугмаси).
      final listingId = (data['listingId'] ?? '').trim();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => YukLocalScreen(
            highlightListingId: listingId.isEmpty ? null : listingId,
          ),
        ),
      );
      return;
    }

    if (type == 'support_chat' || screen == 'chat') {
      await _openChat(nav, data);
      return;
    }

    if (type == 'driver_request_approved') {
      final prefs = await SharedPreferences.getInstance();
      if (!UserAudience.taxiDriverFrom(prefs)) {
        await prefs.remove('pending_driver_open');
        // Эга, 2026-10-31: тасдиқ — табрик (шу телефон + тур учун БИР МАРТА). Кейинги
        // марталар ёки ойна хавфсиз очилмаса (контекст/таржима йўқ) — аввалги snack.
        final ctx = nav.context;
        final celebrated = ctx.mounted &&
            AppLocalizations.of(ctx) != null &&
            await showDriverApprovedCelebrationOnce(
              ctx,
              phone: prefs.getString('user_phone') ?? '',
              taxiType: data['taxiType'],
            );
        if (!celebrated) _showPassiveSnack(nav, 'driver_request_approved_snack');
        return;
      }

      final taxiType = (data['taxiType'] ?? 'local').trim();
      switch (taxiType) {
        case 'marshrut':
          final uid = phoneDigits(prefs.getString('user_phone') ?? '');
          final profile = uid.isNotEmpty
              ? await MarshrutDriverRepository().getProfile(uid)
              : null;
          if (profile != null) {
            await nav.push(
              MaterialPageRoute(
                builder: (_) => DriverPanelMarshrutScreen(
                  carModel: profile.carModel,
                  plate: profile.plate,
                  seats: profile.seats,
                  stops: profile.stops,
                  driverName: profile.driverName,
                  driverPhone: profile.driverPhone,
                  driverId: profile.uid,
                ),
              ),
            );
          } else {
            await nav.push(
              MaterialPageRoute(
                builder: (_) => const DriverRegisterMarshrutScreen(),
              ),
            );
          }
          break;
        case 'intercity':
          final uid = phoneDigits(prefs.getString('user_phone') ?? '');
          final args = uid.length >= 9
              ? await IntercityDriverResume.loadPanelArgs(uid)
              : null;
          if (args != null) {
            await nav.push(
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
          } else {
            await nav.push(
              MaterialPageRoute(
                builder: (_) => const IntercityTaxiScreen(),
              ),
            );
          }
          break;
        default:
          await nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LocalTaxiScreen()),
            (route) => route.isFirst,
          );
      }

      await prefs.remove('pending_driver_open');
      return;
    }

    if (screen == 'relatives' ||
        type == 'relative_registered' ||
        type == 'relative_waiting' ||
        type == 'tree_link_invite') {
      final treeTab = tab == 'tree' || type == 'tree_link_invite';
      await nav.push(
        MaterialPageRoute(
          builder: (_) => RelativesScreen(
            initialTabIndex: treeTab ? 1 : 0,
            openTreeInvites: type == 'tree_link_invite',
          ),
        ),
      );
      return;
    }

    // Танишув — ТАШҚИ Telegram бот (қаранг: `HomeScreen._openDating`).
    // `dating_youth_promo` — фойдаланувчини танишувга таклиф қилувчи
    // хабарнома; у иловадаги БЎШ экранни эмас, айнан ботни очиши керак,
    // акс ҳолда таклиф ҳеч қаерга олиб бормайди.
    if (screen == 'dating' || type == 'dating_youth_promo') {
      await openDatingTelegramBot(nav.context);
      return;
    }

    final newsTab = _newsHubTabIndex(tab: tab, type: type);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => NewsHubScreen(initialTabIndex: newsTab),
      ),
    );
  }

  /// Push'дан очиладиган модул ҳам «＋» ва каталог билан бир қоида (кенгаш P9):
  /// ёпиқ ёки «Тез кунда» бўлса экран очилмайди, сабаби айтилади.
  /// Курьер/ресторан буюртма push'лари бунга кирмайди — улар ишдаги кишининг жорий иши.
  static bool _moduleOpen(NavigatorState nav, String moduleId) {
    if (ServiceConfigHolder.isOpenable(moduleId)) return true;
    final ctx = nav.context;
    if (ctx.mounted) HomeModuleGate.onTapBlocked(ctx, moduleId);
    return false;
  }

  static void _showPassiveSnack(NavigatorState nav, String key) {
    final ctx = nav.context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(ctx)!.translate(key)),
      duration: const Duration(seconds: 3),
    ));
  }

  static Future<void> _openChat(
    NavigatorState nav,
    Map<String, String> data,
  ) async {
    var chatId = phoneDigits(
      data['chatId'] ?? data['userPhone'] ?? '',
    );
    if (chatId.length < 9) {
      final prefs = await SharedPreferences.getInstance();
      chatId = phoneDigits(prefs.getString('user_phone') ?? '');
    }
    if (chatId.length < 9) return;
    await nav.push(
      MaterialPageRoute(builder: (_) => ChatScreen(targetPhone: chatId)),
    );
  }

  /// FCM [data] учун `screen` / `tab` тўлдириш (Cloud Functions билан бирга).
  static Map<String, String> enrichFcmData(Map<String, String> data) {
    final type = data['type'] ?? '';
    final out = Map<String, String>.from(data);
    if (out['screen']?.isNotEmpty == true) return out;

    if (_intercityTypes.contains(type)) {
      out['screen'] = 'intercity';
    } else if (type == 'trip' || type == 'marshrut_request' || type == 'trip_accepted') {
      out['screen'] = 'marshrut';
    } else if (type == 'order' || type.startsWith('order')) {
      out['screen'] = 'news';
      out['tab'] = 'orders';
    } else if (type == 'market_ad_published' || type == 'market_ad_moderation') {
      out['screen'] = 'my_ads';
    } else if (type == 'ad_published' || type == 'ad_moderation') {
      out['screen'] = 'jobs';
    } else if (type == 'sell_offer') {
      // «Сотув маркази» экрани ёпилди — таклиф ҳақидаги хабар
      // Янгиликлар ҳубининг «Хабарлар» табида кўринади.
      out['screen'] = 'news';
      out['tab'] = 'messages';
    } else if (type == 'seller_pickup') {
      out['screen'] = 'seller_pos';
    } else if (type == 'support_chat') {
      out['screen'] = 'chat';
    } else if (type == 'identity' || type == 'general') {
      out['screen'] = 'news';
      out['tab'] = 'messages';
    } else if (type == 'relative_registered' || type == 'relative_waiting') {
      out['screen'] = 'relatives';
    } else if (type == 'tree_link_invite') {
      out['screen'] = 'relatives';
      out['tab'] = 'tree';
    } else if (type == 'dating_youth_promo') {
      out['screen'] = 'dating';
    } else if (type == 'driver_request_approved') {
      out['screen'] = 'local_taxi';
    } else if (type == 'local_trip_accepted') {
      out['screen'] = 'local_taxi';
    } else if (type == 'local_trip_request') {
      out['screen'] = 'local_trip_request';
    }
    return out;
  }

  /// 0 — Янгилик, 1 — Хабарлар, 2 — Буюртма.
  static int _newsHubTabIndex({required String tab, required String type}) {
    if (tab == 'orders' ||
        tab == 'order' ||
        type == 'order' ||
        type.startsWith('order_')) {
      return 2;
    }
    if (tab == 'messages' ||
        tab == 'dialog' ||
        type == 'identity' ||
        type == 'support_chat' ||
        // Эски `screen: 'sell'` payload'лари ҳам шу ерга тушади
        // (`tab: 'forwarded'` бўлиши мумкин — у энди ишлатилмайди).
        type == 'sell_offer') {
      return 1;
    }
    if (tab == 'broadcast' || tab == 'general') return 0;
    return 0;
  }
}
