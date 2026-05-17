import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../repositories/marshrut_driver_repository.dart';
import '../../../repositories/schedules_repository.dart';
import '../../../shared/widgets/mfy_field.dart';
import '../../../shared/widgets/seat_selector.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/gurlan_places.dart';
import '../controllers/driver_schedule_controller.dart';

class DriverScheduleScreen extends StatelessWidget {
  const DriverScheduleScreen({
    super.key,
    required this.taxiType,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
  });

  final String taxiType;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final c = DriverScheduleController(
          taxiType: taxiType,
          driverName: driverName,
          driverPhone: driverPhone,
          driverCar: driverCar,
          driverPlate: driverPlate,
          schedulesRepo: ctx.read<SchedulesRepository>(),
          marshrutDriverRepo: ctx.read<MarshrutDriverRepository>(),
        );
        c.init();
        return c;
      },
      child: const _DriverScheduleView(),
    );
  }
}

class _DriverScheduleView extends StatefulWidget {
  const _DriverScheduleView();

  @override
  State<_DriverScheduleView> createState() => _DriverScheduleViewState();
}

class _DriverScheduleViewState extends State<_DriverScheduleView> {
  static const _green = AppColors.success;
  static const _blue = AppColors.marshrut;

  final _fromSearchCtrl = TextEditingController();
  final _midSearchCtrl = TextEditingController();
  final _toSearchCtrl = TextEditingController();

  final _fromAddrCtrl = TextEditingController();
  final _toAddrCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  String _fromQuery = '';
  bool _showFromSug = false;

  String _midQuery = '';
  bool _showMidSug = false;

  String _toQuery = '';
  bool _showToSug = false;

  List<String> _fromAddrSug = const [];
  List<String> _toAddrSug = const [];
  Timer? _debounce;

  bool _hydrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    final c = context.read<DriverScheduleController>();
    if (c.isMarshrut) {
      if (c.fromMfy.isNotEmpty) _fromSearchCtrl.text = c.fromMfy;
      if (c.toMfy.isNotEmpty) _toSearchCtrl.text = c.toMfy;
    } else {
      if (c.fromAddr.isNotEmpty) _fromAddrCtrl.text = c.fromAddr;
      if (c.toAddr.isNotEmpty) _toAddrCtrl.text = c.toAddr;
    }
    _hydrated = true;
  }

  @override
  void dispose() {
    _fromSearchCtrl.dispose();
    _midSearchCtrl.dispose();
    _toSearchCtrl.dispose();
    _fromAddrCtrl.dispose();
    _toAddrCtrl.dispose();
    _priceCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _pickTime({required bool isStart}) async {
    final c = context.read<DriverScheduleController>();
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? c.startTime : c.endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: _blue)),
        child: child!,
      ),
    );
    if (picked == null) return;
    if (isStart) {
      c.setStartTime(picked);
    } else {
      c.setEndTime(picked);
    }
  }

  void _onFromAddrChanged(String q) {
    context.read<DriverScheduleController>().setFromAddr(q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _fromAddrSug = GurlanPlaces.search(q));
    });
  }

  void _onToAddrChanged(String q) {
    context.read<DriverScheduleController>().setToAddr(q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _toAddrSug = GurlanPlaces.search(q));
    });
  }

  Future<void> _onConfirm() async {
    final c = context.read<DriverScheduleController>();
    final ok = await c.confirm();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else if (c.errorMessage != null) {
      _showError(c.errorMessage!);
      c.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverScheduleController>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Ишга чиқиш'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _fromAddrSug = const [];
            _toAddrSug = const [];
            _showFromSug = false;
            _showToSug = false;
            _showMidSug = false;
          });
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderCard(controller: c),
              const SizedBox(height: 20),
              Row(children: [
                const Icon(Icons.route, color: AppColors.marshrut, size: 20),
                const SizedBox(width: 8),
                const Text('ЙЎНАЛИШ',
                    style: TextStyle(
                        fontSize: AppText.titleSmall,
                        fontWeight: FontWeight.bold,
                        color: AppColors.marshrut,
                        letterSpacing: 1.2)),
              ]),
              const SizedBox(height: 12),
              if (c.isMarshrut) ...[
                _buildMarshrutStops(c),
                const SizedBox(height: 20),
              ] else ...[
                _addressField(
                  ctrl: _fromAddrCtrl,
                  hint: 'ҚАЕРДАН — МФЙ, бозор, маҳалла...',
                  icon: Icons.circle_outlined,
                  iconColor: Colors.green,
                  onChanged: _onFromAddrChanged,
                ),
                if (_fromAddrSug.isNotEmpty)
                  _suggestList(_fromAddrSug, _fromAddrCtrl, (v) {
                    context.read<DriverScheduleController>().setFromAddr(v);
                  }, () {
                    setState(() => _fromAddrSug = const []);
                  }),
                const SizedBox(height: 8),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      final tmp = _fromAddrCtrl.text;
                      _fromAddrCtrl.text = _toAddrCtrl.text;
                      _toAddrCtrl.text = tmp;
                      context.read<DriverScheduleController>().swapAddrs();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.marshrut.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.marshrut.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.swap_vert,
                          color: AppColors.marshrut, size: 22),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _addressField(
                  ctrl: _toAddrCtrl,
                  hint: 'ҚАЕРГА — МФЙ, бозор, маҳалла...',
                  icon: Icons.location_on,
                  iconColor: Colors.red,
                  onChanged: _onToAddrChanged,
                ),
                if (_toAddrSug.isNotEmpty)
                  _suggestList(_toAddrSug, _toAddrCtrl, (v) {
                    context.read<DriverScheduleController>().setToAddr(v);
                  }, () {
                    setState(() => _toAddrSug = const []);
                  }),
                const SizedBox(height: 20),
              ],
              if (c.isIntercity) ...[
                _sectionTitle('💰 Йўлкира нархи (сўм)'),
                const SizedBox(height: 8),
                _textField(
                  ctrl: _priceCtrl,
                  hint: 'Масалан: 150000',
                  icon: Icons.monetization_on_outlined,
                  inputType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: c.setPriceText,
                ),
                const SizedBox(height: 20),
              ],
              if (c.isAlone) ...[
                _sectionTitle('🕐 Иш вақти'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _timeCard('Бошланиш', _fmt(c.startTime),
                          () => _pickTime(isStart: true))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _timeCard('Тугаш', _fmt(c.endTime),
                          () => _pickTime(isStart: false))),
                ]),
                const SizedBox(height: 20),
              ],
              _SeatsCard(controller: c),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: c.isSaving ? null : _onConfirm,
                  icon: c.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: Text(
                    c.isSaving ? 'Сақланмоқда...' : 'ИШГА ЧИҚИШНИ ТАСДИҚЛАЙМАН',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                  child: Text('Иш санаси ярим тунда автоматик ёпилади',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarshrutStops(DriverScheduleController c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stopLabel('📍 Бошлангич нуқта', required: true),
      const SizedBox(height: 6),
      MfyField(
        ctrl: _fromSearchCtrl,
        hint: 'МФЙ танланг...',
        iconColor: Colors.green,
        showSug: _showFromSug,
        query: _fromQuery,
        onChanged: (q) => setState(() {
          _fromQuery = q;
          _showFromSug = q.length >= 2;
        }),
        onSelected: (v) {
          c.setFromMfy(v);
          _fromSearchCtrl.text = v;
          setState(() => _showFromSug = false);
        },
        onClear: () {
          c.setFromMfy('');
          _fromSearchCtrl.clear();
          setState(() => _showFromSug = false);
        },
      ),
      const SizedBox(height: 16),
      Row(children: [
        _stopLabel('🔵 Оралиқ тўхташ нуқталари', required: false),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8)),
          child: Text('ИХТИЁРИЙ',
              style: TextStyle(
                  fontSize: AppText.labelTiny,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      ...c.midStops.asMap().entries.map((e) {
        final i = e.key;
        final stop = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _blue.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.radio_button_unchecked,
                color: Colors.blueGrey, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(stop,
                    style: const TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.w500))),
            GestureDetector(
                onTap: () => c.removeMidStop(i),
                child: Icon(Icons.close,
                    size: 16, color: Colors.grey.shade400)),
          ]),
        );
      }),
      MfyField(
        ctrl: _midSearchCtrl,
        hint: '+ Оралиқ нуқта қўшиш...',
        iconColor: Colors.blueGrey,
        showSug: _showMidSug,
        query: _midQuery,
        onChanged: (q) => setState(() {
          _midQuery = q;
          _showMidSug = q.length >= 2;
        }),
        onSelected: (v) {
          final ok = c.addMidStop(v);
          if (!ok) {
            if (c.errorMessage != null) {
              _showError(c.errorMessage!);
              c.clearError();
            }
            return;
          }
          _midSearchCtrl.clear();
          setState(() {
            _midQuery = '';
            _showMidSug = false;
          });
        },
        onClear: () {
          _midSearchCtrl.clear();
          setState(() {
            _midQuery = '';
            _showMidSug = false;
          });
        },
      ),
      const SizedBox(height: 16),
      _stopLabel('🏁 Охирги нуқта', required: true),
      const SizedBox(height: 6),
      MfyField(
        ctrl: _toSearchCtrl,
        hint: 'МФЙ танланг...',
        iconColor: Colors.red,
        showSug: _showToSug,
        query: _toQuery,
        onChanged: (q) => setState(() {
          _toQuery = q;
          _showToSug = q.length >= 2;
        }),
        onSelected: (v) {
          c.setToMfy(v);
          _toSearchCtrl.text = v;
          setState(() => _showToSug = false);
        },
        onClear: () {
          c.setToMfy('');
          _toSearchCtrl.clear();
          setState(() => _showToSug = false);
        },
      ),
      if (c.fromMfy.isNotEmpty && c.toMfy.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _blue.withOpacity(0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.route, color: AppColors.marshrut, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(c.allStops.join(' → '),
                    style: const TextStyle(
                        fontSize: AppText.labelSmall,
                        color: AppColors.marshrut,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
      ],
    ]);
  }

  Widget _stopLabel(String text, {required bool required}) {
    return Row(children: [
      Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      if (required) ...[
        const SizedBox(width: 4),
        const Text('*', style: TextStyle(color: Colors.red, fontSize: 14))
      ],
    ]);
  }

  Widget _addressField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: iconColor, size: 18),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.marshrut, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _suggestList(
    List<String> items,
    TextEditingController ctrl,
    ValueChanged<String> onPick,
    VoidCallback onDismiss,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
          children: items
              .map((p) => InkWell(
                    onTap: () {
                      ctrl.text = p;
                      onPick(p);
                      onDismiss();
                      FocusScope.of(context).unfocus();
                    },
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.location_on,
                              size: 14, color: AppColors.marshrut),
                          const SizedBox(width: 8),
                          Text(p, style: const TextStyle(fontSize: 13)),
                        ])),
                  ))
              .toList()),
    );
  }

  Widget _timeCard(String label, String time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
            ]),
        child: Row(children: [
          const Icon(Icons.access_time, color: AppColors.marshrut, size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            Text(time,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.marshrut)),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
        ]),
      ),
    );
  }

  Widget _textField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter> formatters = const [],
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
          ]),
      child: TextField(
        controller: ctrl,
        keyboardType: inputType,
        inputFormatters: formatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: _blue, size: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.marshrut, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.controller});
  final DriverScheduleController controller;

  String _emoji() {
    switch (controller.taxiType) {
      case 'marshrut':
        return '🚐';
      case 'intercity':
        return '🚌';
      default:
        return '🚕';
    }
  }

  String _label() {
    switch (controller.taxiType) {
      case 'marshrut':
        return 'Маршрут такси';
      case 'intercity':
        return 'Шаҳарлараро такси';
      default:
        return 'Маҳаллий такси';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.marshrut.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.marshrut.withOpacity(0.2)),
      ),
      child: Row(children: [
        Text(_emoji(), style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_label(),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.marshrut)),
          Text('${controller.driverCar} · ${controller.driverPlate}',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ]),
    );
  }
}

class _SeatsCard extends StatelessWidget {
  const _SeatsCard({required this.controller});
  final DriverScheduleController controller;

  static const _blue = AppColors.marshrut;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('💺 Бўш ўринлар сони (максимум ${c.maxSeats})',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
            onTap: () {
              if (c.seats > 1) c.setSeats(c.seats - 1);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.seats > 1
                    ? const Color(0xFFE3F2FD)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: c.seats > 1 ? _blue : Colors.grey.shade300),
              ),
              child: Icon(Icons.remove,
                  color: c.seats > 1 ? _blue : Colors.grey, size: 20),
            ),
          ),
          const SizedBox(width: 24),
          Column(children: [
            Text('${c.seats}',
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.marshrut)),
            Text('ўрин',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              if (c.seats < c.maxSeats) c.setSeats(c.seats + 1);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.seats < c.maxSeats
                    ? const Color(0xFFE3F2FD)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                        c.seats < c.maxSeats ? _blue : Colors.grey.shade300),
              ),
              child: Icon(Icons.add,
                  color: c.seats < c.maxSeats ? _blue : Colors.grey,
                  size: 20),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SeatSelector(
          value: c.seats,
          maxSeats: c.maxSeats,
          color: _blue,
          onChanged: c.setSeats,
        ),
      ]),
    );
  }
}
