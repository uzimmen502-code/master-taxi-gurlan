import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/driver_schedule/screens/driver_schedule_screen.dart';

/// Haydovchi sifatida ishga chiqish flow'i: профил телефон/исм + (керакли)
/// машина маркаси/давlat raqamini сўрайди ва `DriverScheduleScreen`-ga
/// о'тади.
///
/// `car_model` ва `car_plate` SharedPreferences'da сақланса — қайта
/// сўрамайди, диалог ўтказиб юборилади. Бу UX: фойдаланувчи биринчи марта
/// маълумотларни киритса, кейинги мартани диалогсиз ишга чиқади.
///
/// `taxiType`: `'alone'` | `'marshrut'` | `'intercity'` — `DriverScheduleScreen`
/// 3 та оқимни шу параметр бўйича фарқлайди.
Future<void> showDriverCarInfoDialog({
  required BuildContext context,
  required String taxiType,
  required Color primaryColor,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('user_phone') ?? '';
  final name = prefs.getString('user_name') ?? '';
  final uid = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (!context.mounted) return;
  if (uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Аввал профилдан телефон рақамини киритинг')));
    return;
  }

  final carModel = prefs.getString('car_model') ?? '';
  final carPlate = prefs.getString('car_plate') ?? '';
  if (carModel.isNotEmpty && carPlate.isNotEmpty) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverScheduleScreen(
          taxiType: taxiType,
          driverName: name,
          driverPhone: phone,
          driverCar: carModel,
          driverPlate: carPlate,
        ),
      ),
    );
    return;
  }

  final carCtrl = TextEditingController();
  final plateCtrl = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('🚗 Машина маълумотлари'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: carCtrl,
            decoration: const InputDecoration(
                hintText: 'Машина маркаси', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: plateCtrl,
            decoration: const InputDecoration(
                hintText: 'Давлат рақами', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Бекор')),
        ElevatedButton(
          onPressed: () async {
            final car = carCtrl.text.trim();
            final plate = plateCtrl.text.trim();
            if (car.isEmpty || plate.isEmpty) return;
            await prefs.setString('car_model', car);
            await prefs.setString('car_plate', plate);
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverScheduleScreen(
                  taxiType: taxiType,
                  driverName: name,
                  driverPhone: phone,
                  driverCar: car,
                  driverPlate: plate,
                ),
              ),
            );
          },
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
          child:
              const Text('ДАВОМ ЭТИШ', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
