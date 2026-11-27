import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/widgets/home_lite_cards.dart';
import '../car_insurance_service.dart';
import '../screens/car_insurance_screen.dart';

/// Эга расми (2026-11-28, 32.webp дан 400×267 webp; ўзгарса — `_v2`).
const kCarInsuranceCardImage = 'assets/images/services/card_car_insurance_v1.webp';

/// Бош саҳифа карточкаси id (`home_lite_card_car_insurance`).
const kCarInsuranceHomeCardId = 'car_insurance';

/// Сессия кеши: телефон → ҳолат (37-банд: ҳар бош саҳифа очилишида callable эмас).
final Map<String, Future<InsuranceState>> _stateCache = {};

@visibleForTesting
void resetCarInsuranceStateCache() => _stateCache.clear();

/// Ҳолат (кешли). Хато — «мавжуд эмас» (карточка кўринмайди), кеш тозаланади.
Future<InsuranceState> carInsuranceStateCached(
  String phone, {
  CarInsuranceService? service,
  Future<InsuranceState> Function()? loader,
  bool refresh = false,
}) {
  if (phone.isEmpty) return Future.value(InsuranceState.unavailable);
  if (refresh) _stateCache.remove(phone);
  return _stateCache.putIfAbsent(phone, () async {
    try {
      return await (loader?.call() ?? (service ?? CarInsuranceService()).myState());
    } catch (e) {
      debugPrint('[CarInsurance] INSURANCE_STATE_FAILED: $e');
      _stateCache.remove(phone);
      return InsuranceState.unavailable;
    }
  });
}

/// Бош саҳифа ДАРВОЗАСИ: сервер босқичи (`insurance_config/main.stage` off/internal/pilot/public, сукут OFF) —
/// `insuranceGetMyState.available`. Кешли; хато → `false`.
Future<bool> carInsuranceHomeVisible(String phone, {Future<InsuranceState> Function()? loader, bool refresh = false}) async =>
    (await carInsuranceStateCached(phone, loader: loader, refresh: refresh)).available;

/// «Эълон ва хизматлар» учун карточка маълумоти (жойлаш — бош саҳифа layout'и; кўрсатишдан олдин
/// [carInsuranceHomeVisible] текширилсин). [onReturn] — экрандан қайтгач (масалан, дарвозани янгилаш).
HomeLiteCardData carInsuranceHomeCard(BuildContext context, {required String phone, VoidCallback? onReturn}) =>
    HomeLiteCardData(
      id: kCarInsuranceHomeCardId,
      title: context.tr('ins_home_title'),
      caption: context.tr('ins_home_caption'),
      imagePath: kCarInsuranceCardImage,
      fit: HomeLiteImageFit.cover,
      onTap: () async {
        await openCarInsurance(context, phone);
        _stateCache.remove(phone);
        onReturn?.call();
      },
    );

Future<void> openCarInsurance(BuildContext context, String phone, {CarInsuranceService? service}) =>
    openCarInsuranceWith(Navigator.of(context), phone, service: service);

/// Push ва бошқа контекстсиз жойлар учун.
Future<void> openCarInsuranceWith(NavigatorState nav, String phone, {CarInsuranceService? service}) =>
    nav.push(MaterialPageRoute<void>(builder: (_) => CarInsuranceScreen(phone: phone, service: service)));

/// «Менинг машинам» экранидаги қатор: суғурта муддати + «Автомобил суғуртаси» га ўтиш (мавжуд бўлса).
class CarInsuranceAutoHubTile extends StatefulWidget {
  const CarInsuranceAutoHubTile({super.key, required this.phone, this.loader});
  final String phone;
  final Future<InsuranceState> Function()? loader;

  @override
  State<CarInsuranceAutoHubTile> createState() => _CarInsuranceAutoHubTileState();
}

class _CarInsuranceAutoHubTileState extends State<CarInsuranceAutoHubTile> {
  late Future<InsuranceState> _state = carInsuranceStateCached(widget.phone, loader: widget.loader);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InsuranceState>(
      future: _state,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null || !s.available) return const SizedBox.shrink();
        final left = insuranceDaysLeft(s.expiresOn, DateTime.now());
        final soon = left != null && left <= 4;
        return Card(
          key: const ValueKey('auto_hub_insurance'),
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(Icons.shield_outlined, color: AppColors.primary, size: 30),
            title: Text(context.tr('ins_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              s.expiresOn.isEmpty
                  ? context.tr('ins_expiry_none')
                  : context.tr('ins_autohub_until').replaceAll('{date}', insuranceDisplayDate(s.expiresOn)),
              style: soon ? TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600) : null,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await openCarInsurance(context, widget.phone);
              if (mounted) setState(() => _state = carInsuranceStateCached(widget.phone, loader: widget.loader, refresh: true));
            },
          ),
        );
      },
    );
  }
}
