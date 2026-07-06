import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/intercity_taxi/driver/intercity_driver_resume.dart';
import '../features/intercity_taxi/driver/screens/intercity_driver_panel_screen.dart';
import '../features/intercity_taxi/passenger/screens/intercity_taxi_screen.dart';
import '../features/relatives/screens/relatives_screen.dart';
import '../l10n/app_localizations.dart';
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
import '../features/sell/screens/sell_offer_screen.dart';
import '../main.dart';

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

  static Future<void> handlePayload(String? payload) async {
    await handleData(decodePayload(payload));
  }

  static Future<void> handleData(Map<String, String> data) async {
    final nav = MyApp.navigatorKey.currentState;
    if (nav == null) return;

    final type = (data['type'] ?? '').trim();
    final screen = (data['screen'] ?? '').trim();
    final tab = (data['tab'] ?? '').trim();

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
      final userRole = prefs.getString('user_role') ?? 'user';
      if (userRole != 'driver') {
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

    if (screen == 'jobs' ||
        type == 'ad_published' ||
        type == 'ad_moderation') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const JobsScreen()),
      );
      return;
    }

    if (screen == 'sell' || type == 'sell_offer') {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.length < 9) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => SellOfferScreen(
            phone: phone,
            defaultToPlatform: false,
            defaultToPublic: true,
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
      final userRole = prefs.getString('user_role') ?? 'user';
      if (userRole != 'driver') {
        _showPassiveSnack(nav, 'driver_request_approved_snack');
        await prefs.remove('pending_driver_open');
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

    final newsTab = _newsHubTabIndex(tab: tab, type: type);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => NewsHubScreen(initialTabIndex: newsTab),
      ),
    );
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
    } else if (type == 'ad_published' || type == 'ad_moderation') {
      out['screen'] = 'jobs';
    } else if (type == 'sell_offer') {
      out['screen'] = 'sell';
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
        type == 'support_chat') {
      return 1;
    }
    if (tab == 'broadcast' || tab == 'general') return 0;
    return 0;
  }
}
