import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../repositories/marshrut_driver_repository.dart';
import 'driver_panel_marshrut_screen.dart';
import '../../../../utils/app_theme.dart';
import '../controllers/marshrut_register_controller.dart';
import '../../../../shared/widgets/mfy_field.dart';
import '../../../../shared/widgets/seat_selector.dart';

/// Marshrut haydovchi ro'yxatdan o'tish / profilini yangilash ekrani.
class DriverRegisterMarshrutScreen extends StatelessWidget {
  const DriverRegisterMarshrutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutRegisterController>(
      create: (ctx) => MarshrutRegisterController(
          repo: ctx.read<MarshrutDriverRepository>())
        ..init(),
      child: const _DriverRegisterMarshrutView(),
    );
  }
}

class _DriverRegisterMarshrutView extends StatefulWidget {
  const _DriverRegisterMarshrutView();

  @override
  State<_DriverRegisterMarshrutView> createState() =>
      _DriverRegisterMarshrutViewState();
}

class _DriverRegisterMarshrutViewState
    extends State<_DriverRegisterMarshrutView> {
  static const Color _color = Color(0xFF00695C);

  final _carModelCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _midCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  String _fromQuery = '';
  String _midQuery = '';
  String _toQuery = '';
  bool _showFromSug = false;
  bool _showMidSug = false;
  bool _showToSug = false;

  bool _formHydrated = false;
  String? _lastErrorShown;
  bool _missingPhoneHandled = false;

  @override
  void dispose() {
    _carModelCtrl.dispose();
    _plateCtrl.dispose();
    _fromCtrl.dispose();
    _midCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _hydrateForm(MarshrutRegisterController c) {
    if (_formHydrated || c.isLoading) return;
    _formHydrated = true;
    _carModelCtrl.text = c.carModel;
    _plateCtrl.text = c.plate;
    _fromCtrl.text = c.fromMfy;
    _toCtrl.text = c.toMfy;
  }

  void _handleSideEffects(MarshrutRegisterController c) {
    if (c.missingPhone && !_missingPhoneHandled) {
      _missingPhoneHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Аввал профилдан телефон рақамини киритинг'),
          backgroundColor: Colors.red,
        ));
        Navigator.pop(context);
      });
      return;
    }

    if (c.errorMessage != null && c.errorMessage != _lastErrorShown) {
      _lastErrorShown = c.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(c.errorMessage!);
        c.clearTransient();
        _lastErrorShown = null;
      });
    }

    if (c.savedProfile != null) {
      final p = c.savedProfile!;
      c.clearTransient();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverPanelMarshrutScreen(
              carModel: p.carModel,
              plate: p.plate,
              seats: p.seats,
              stops: p.stops,
              driverName: p.driverName,
              driverPhone: p.driverPhone,
              driverId: p.uid,
            ),
          ),
        );
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MarshrutRegisterController>();
    _hydrateForm(c);
    _handleSideEffects(c);

    if (c.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE0F2F1),
      appBar: AppBar(
        title: Text(c.isRegistered ? '🚐 Маршрут профили' : '🚐 Маршрут ҳайдовчиси'),
        backgroundColor: _color,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _showFromSug = false;
            _showMidSug = false;
            _showToSug = false;
          });
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Banner(isRegistered: c.isRegistered),
                const SizedBox(height: 20),
                _sectionTitle('🚗 Машина маълумотлари'),
                const SizedBox(height: 10),
                _carRow(c),
                const SizedBox(height: 12),
                _label('💺 Ўрин сони (максимум ${c.maxSeats})'),
                const SizedBox(height: 10),
                SeatSelector(
                  value: c.seats,
                  maxSeats: c.maxSeats,
                  onChanged: c.setSeats,
                ),
                const SizedBox(height: 24),
                _sectionTitle('📍 Маршрут нуқталари'),
                const SizedBox(height: 4),
                Text('Бошлангич ва охирги нуқта мажбурий',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 12),
                _stopLabel('📍 Бошлангич нуқта', required: true),
                const SizedBox(height: 6),
                MfyField(
                  ctrl: _fromCtrl,
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
                    _fromCtrl.text = v;
                    setState(() => _showFromSug = false);
                  },
                  onClear: () {
                    c.setFromMfy('');
                    _fromCtrl.clear();
                    setState(() => _showFromSug = false);
                  },
                ),
                const SizedBox(height: 16),
                _midStopsHeader(),
                const SizedBox(height: 8),
                ..._midStopsList(c),
                MfyField(
                  ctrl: _midCtrl,
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
                      _snack('Бу нуқта аллақачон қўшилган');
                      return;
                    }
                    _midCtrl.clear();
                    setState(() {
                      _midQuery = '';
                      _showMidSug = false;
                    });
                  },
                  onClear: () {
                    _midCtrl.clear();
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
                  ctrl: _toCtrl,
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
                    _toCtrl.text = v;
                    setState(() => _showToSug = false);
                  },
                  onClear: () {
                    c.setToMfy('');
                    _toCtrl.clear();
                    setState(() => _showToSug = false);
                  },
                ),
                if (c.fromMfy.isNotEmpty && c.toMfy.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _routePreview(c.allStops),
                ],
                const SizedBox(height: 32),
                _saveButton(c),
                const SizedBox(height: 16),
              ]),
        ),
      ),
    );
  }

  Widget _carRow(MarshrutRegisterController c) {
    return Row(children: [
      Expanded(
        flex: 2,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Машина'),
          const SizedBox(height: 6),
          _PlainField(
            ctrl: _carModelCtrl,
            hint: 'Cobalt',
            onChanged: c.setCarModel,
          ),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('Рақам'),
          const SizedBox(height: 6),
          _PlainField(
            ctrl: _plateCtrl,
            hint: '01A123BC',
            onChanged: c.setPlate,
          ),
        ]),
      ),
    ]);
  }

  Widget _midStopsHeader() {
    return Row(children: [
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
    ]);
  }

  List<Widget> _midStopsList(MarshrutRegisterController c) {
    return [
      for (var i = 0; i < c.midStops.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _color.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.radio_button_unchecked,
                color: Colors.blueGrey, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(c.midStops[i],
                    style: const TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.w500))),
            GestureDetector(
              onTap: () => c.removeMidStop(i),
              child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
            ),
          ]),
        ),
    ];
  }

  Widget _routePreview(List<String> stops) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withOpacity(0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.route, color: _color, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(
          stops.join(' → '),
          style: const TextStyle(
              fontSize: AppText.labelSmall,
              color: _color,
              fontWeight: FontWeight.w600),
        )),
      ]),
    );
  }

  Widget _saveButton(MarshrutRegisterController c) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: c.isSaving ? null : c.save,
        icon: c.isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle, size: 22),
        label: Text(
          c.isSaving
              ? 'Сақланмоқда...'
              : c.isRegistered
                  ? 'ЯНГИЛАШ ВА БОШЛАШ'
                  : 'САҚЛАШ ВА БОШЛАШ',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800));

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));

  Widget _stopLabel(String text, {required bool required}) {
    return Row(children: [
      Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      if (required) ...[
        const SizedBox(width: 4),
        const Text('*', style: TextStyle(color: Colors.red, fontSize: 14)),
      ],
    ]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.isRegistered});

  final bool isRegistered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Text('🚐', style: TextStyle(fontSize: 32)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Маршрут такси ҳайдовчиси',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text(
                isRegistered
                    ? 'Маълумотларингизни янгиланг'
                    : 'Бир марта киритинг — доим сақланади',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withOpacity(0.85)),
              ),
            ])),
      ]),
    );
  }
}

class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.ctrl,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
        ],
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
