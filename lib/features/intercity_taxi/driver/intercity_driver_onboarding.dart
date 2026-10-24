import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../shared/navigation/ensure_car_info_via_profile.dart';
import '../../../shared/widgets/driver_car_info_dialog.dart';
import '../../../shared/widgets/driver_application_feedback.dart';
import '../../../shared/widgets/taxi_agreement_sheet.dart';
import '../passenger/intercity_colors.dart';
import 'intercity_driver_resume.dart';
import 'screens/intercity_driver_panel_screen.dart';
import '../../../services/user_audience.dart';

/// «Ҳайдовчи бўлиш» — шаҳарлараро: рўйхатдан ўтиш ва ишга чиқиш БИТТА
/// узлуксиз оқим. Аввал ҳайдовчи рўйхатдан ўтгач яна тугмани босиши керак
/// эди; энди рўйхатдан ўтиш тугагач дарҳол рейс очиш ойнаси чиқади.
///
/// Экрандан ҳам, бош саҳифадаги «＋» менюсидан ҳам чақирилади.
class IntercityDriverOnboarding {
  IntercityDriverOnboarding._();

  /// Хатолар шу ерда ушланади ва содда матн билан кўрсатилади — жим
  /// йиқилиш йўқ.
  static Future<void> run(BuildContext context) async {
    try {
      await _run(context);
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      final blocked =
          e.code == 'failed-precondition' || e.code == 'permission-denied';
      _snack(
        context,
        blocked
            ? context.tr('taxi_not_allowed')
            : userErrorMessage(context, e, fallbackKey: 'driver_mode_error'),
        IntercityColors.danger,
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(
        context,
        userErrorMessage(context, e, fallbackKey: 'driver_mode_error'),
        IntercityColors.danger,
      );
    }
  }

  static Future<void> _run(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);
    if (!context.mounted) return;

    if (uid.length < 9) {
      _snack(context, context.tr('fill_phone_in_profile'),
          IntercityColors.warning);
      return;
    }

    // Бекор қилинса — шу экранда қолади (бош саҳифага улоқтирилмайди).
    if (!await ensureCarInfoViaProfile(context, goHomeOnCancel: false)) return;
    if (!context.mounted) return;

    final driverRepo = context.read<DriverRepository>();
    final access = await driverRepo.taxiAccess(uid: uid, taxiType: 'intercity');
    if (!context.mounted) return;

    if (access.approved) {
      // D-TAXI-24.1: starter тугаган (`verification_required`) — келишувни
      // тизим ўзи тақдим қилади; рад этилса ҳам мавжуд иш давом этади
      // (D-TAXI-5), янги пуллик рейс олдидан сервер яна сўрайди.
      if (access.status == 'verification_required') {
        await ensureTaxiCapability(
          context,
          requestCapability: driverRepo.requestTaxiCapability,
          primaryColor: IntercityColors.primary,
        );
        if (!context.mounted) return;
      }
      await _openWorkspace(context, uid);
      return;
    }

    // D-TAXI-1 / D-TAXI-24.1: дарҳол `starter` — келишувсиз, админ тасдиғисиз.
    final capOk = await ensureTaxiCapability(
      context,
      requestCapability: driverRepo.requestTaxiCapability,
      primaryColor: IntercityColors.primary,
    );
    if (!capOk || !context.mounted) return;

    final carFromProfile =
        await UserRepository().getCarInfo(canonicalPhoneId(uid));
    if (carFromProfile == null || !context.mounted) return;
    final carModel = carFromProfile['carModel'] ?? '';
    final carColor = carFromProfile['carColor'] ?? '';
    final carPlate = carFromProfile['carPlate'] ?? '';
    await prefs.setString('car_model', carModel);
    await prefs.setString('car_color', carColor);
    await prefs.setString('car_plate', carPlate);
    final carSeats = int.tryParse(carFromProfile['carSeats'] ?? '') ?? 0;
    if (carSeats > 0) await prefs.setInt('car_seats', carSeats);

    final name = prefs.getString('user_name') ?? '';
    final car = '$carModel${carColor.isEmpty ? '' : ' · $carColor'}';

    // Йўналиш бу ерда сўралмайди: шаҳарлараро учун уни ҳеч ким ўқимайди,
    // рейс очишда йўналиш барибир қайта киритилади.
    final submitResult = await driverRepo.submitDriverApplication(
      uid: uid,
      name: name,
      phone: phone,
      car: car,
      plate: carPlate,
      taxiType: 'intercity',
    );
    if (!context.mounted) return;

    if (submitResult.autoApproved) {
      await UserAudience.saveTaxiDriver(true);
      if (!context.mounted) return;
      _snack(context, context.tr('intercity_driver_mode_activated'),
          IntercityColors.primary);
      // Рўйхатдан ўтгач ҳайдовчи тугмани қайта босмасин — дарҳол рейс очади.
      await _openWorkspace(context, uid);
    } else {
      await showDriverApplicationPendingFeedback(
        context,
        result: submitResult,
        resentMessageKey: 'intercity_driver_request_sent',
        snackColor: IntercityColors.warning,
      );
    }
  }

  /// Фаол рейс бўлса — панель; йўқ бўлса — рейс очиш ойнаси, кейин панель.
  static Future<void> _openWorkspace(BuildContext context, String uid) async {
    if (await IntercityDriverResume.openPanelIfActive(context, driverId: uid)) {
      return;
    }
    if (!context.mounted) return;
    final started = await showDriverCarInfoDialog(
      context: context,
      taxiType: 'intercity',
      primaryColor: IntercityColors.primary,
    );
    if (!context.mounted || !started) return;
    final args = await IntercityDriverResume.loadPanelArgs(uid);
    if (args == null || !context.mounted) return;
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
  }

  static void _snack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(
        message,
        style: color == IntercityColors.primary
            ? const TextStyle(color: IntercityColors.onPrimary)
            : null,
      ),
    ));
  }
}
