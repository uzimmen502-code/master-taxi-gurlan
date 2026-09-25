import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/ev_station_repository.dart';
import '../../../repositories/user_repository.dart';

/// ⚡ Зарядлаш станциясини қўшиш — ПУЛЛИК (эга қарори, 2026-09-22): харита
/// экранидаги FAB босилганда очиладиган тариф + қадамлар варақаси.
/// `Navigator.pop(context, EvStationTariff)` — танланган тариф билан
/// [AddEvStationScreen]га ўтиш учун; `null` — бекор қилинди.
class EvStationTariffSheet extends StatefulWidget {
  const EvStationTariffSheet({super.key, required this.uid});

  final String uid;

  @override
  State<EvStationTariffSheet> createState() => _EvStationTariffSheetState();
}

class _EvStationTariffSheetState extends State<EvStationTariffSheet> {
  Map<String, EvStationTariff>? _tariffs;
  int? _balance;
  String? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        context.read<EvStationRepository>().fetchStationTariffs(),
        context.read<UserRepository>().watchBonusBalance(widget.uid).first,
      ]);
      if (!mounted) return;
      final tariffs = results[0] as Map<String, EvStationTariff>;
      setState(() {
        _tariffs = tariffs;
        _balance = results[1] as int;
        // Кўпроқ муддатли (одатда энг фойдали) тарифни олдиндан танлаймиз.
        _selectedId = tariffs.values
            .fold<EvStationTariff?>(null, (best, t) =>
                best == null || t.months > best.months ? t : best)
            ?.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Тарифларни юклаб бўлмади. Интернетни текшириб, қайта уриниб кўринг.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: SafeArea(
        top: false,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? _ErrorBody(message: _error!, onRetry: () {
                    setState(() => _loading = true);
                    _load();
                  })
                : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final tariffs = _tariffs!.values.toList()
      ..sort((a, b) => a.months.compareTo(b.months));
    final selected = _selectedId != null ? _tariffs![_selectedId] : null;
    final balance = _balance ?? 0;
    final insufficient = selected != null && balance < selected.price;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.ev_station_rounded, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Зарядлаш станциясини қўшиш',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Ўз (ёки бошқа) зарядлаш станциянгизни расмий рўйхатга киритиш '
            'учун — обуна тарифини танланг:',
            style: TextStyle(fontSize: 13.5, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final t in tariffs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TariffTile(
                tariff: t,
                selected: t.id == _selectedId,
                onTap: () => setState(() => _selectedId = t.id),
              ),
            ),
          if (insufficient)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF8D6E00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ҳамёнда ${formatMoney(balance)} бор — тарифни тўлаш учун '
                      'етарли эмас, аввал ҳамённи тўлдиринг.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF8D6E00)),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
          const Text(
            'Тўловни амалга ошириш қадамлари',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const _Step(number: 1, text: 'Харитадан станция турган аниқ жойни танланг.'),
          const _Step(
              number: 2,
              text: 'Станция маълумотларини тўлдиринг (қувват, разъём тури — '
                  'ихтиёрий, кейин ҳам тўлдириш мумкин).'),
          const _Step(number: 3, text: 'Тарифни танлаб, тасдиқласангиз — тўлов AVA ҳамёнидан ечилади.'),
          const _Step(number: 4, text: 'Станция шу заҳоти харитада барчага кўринади.'),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                selected == null
                    ? 'Давом этиш'
                    : 'Давом этиш — ${formatMoney(selected.price)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TariffTile extends StatelessWidget {
  const _TariffTile({required this.tariff, required this.selected, required this.onTap});

  final EvStationTariff tariff;
  final bool selected;
  final VoidCallback onTap;

  String get _label {
    if (tariff.months % 12 == 0 && tariff.months >= 12) {
      final years = tariff.months ~/ 12;
      return years == 1 ? '1 йиллик обуна' : '$years йиллик обуна';
    }
    return '${tariff.months} ойлик обуна';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AvaLight.surface2 : const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryDark : Colors.black12,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primaryDark : Colors.black38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_label,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('битта станция учун',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Text(
                formatMoney(tariff.price),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Қайта уриниш')),
        ],
      ),
    );
  }
}
