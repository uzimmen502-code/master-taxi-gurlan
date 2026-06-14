import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../repositories/marshrut_driver_repository.dart';
import '../../../../utils/gurlan_places.dart';
import 'driver_panel_marshrut_screen.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/marshrut_register_controller.dart';
import '../../../../shared/widgets/mfy_field.dart';

/// Marshrut haydovchi ro'yxatdan o'tish / profilini yangilash ekrani.
class DriverRegisterMarshrutScreen extends StatelessWidget {
  const DriverRegisterMarshrutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MarshrutRegisterController>(
      create: (ctx) =>
          MarshrutRegisterController(repo: ctx.read<MarshrutDriverRepository>())
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
  static const Color _color = AppColors.button;

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
    _fromCtrl.dispose();
    _midCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _hydrateForm(MarshrutRegisterController c) {
    if (_formHydrated || c.isLoading) return;
    _formHydrated = true;
    _fromCtrl.text = c.fromMfy;
    _toCtrl.text = c.toMfy;
  }

  void _handleSideEffects(MarshrutRegisterController c) {
    if (c.missingPhone && !_missingPhoneHandled) {
      _missingPhoneHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('fill_phone_in_profile')),
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
        _snack(context.trMsg(c.errorMessage!));
        c.clearTransient();
        _lastErrorShown = null;
      });
    }

    if (c.savedProfile != null) {
      final p = c.savedProfile!;
      c.clearTransient();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final repo = context.read<MarshrutDriverRepository>();
        final fromMfy =
            p.stops.isNotEmpty ? p.stops.first : c.fromMfy;
        final toMfy = p.stops.isNotEmpty ? p.stops.last : c.toMfy;
        if (fromMfy.isNotEmpty && toMfy.isNotEmpty) {
          final existing =
              await repo.getRouteCoordinates(fromMfy, toMfy);
          if (existing == null) {
            await _showCoordinatePickerIfNeeded(
              context,
              fromMfy: fromMfy,
              toMfy: toMfy,
              driverId: p.uid,
              repo: repo,
            );
          }
        }
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

  Future<void> _showCoordinatePickerIfNeeded(
    BuildContext context, {
    required String fromMfy,
    required String toMfy,
    required String driverId,
    required MarshrutDriverRepository repo,
  }) async {
    final key = MarshrutDriverRepository.routeKey(fromMfy, toMfy);
    final snap = await FirebaseFirestore.instance
        .collection('marshrut_coordinates')
        .doc(key)
        .get();
    final count =
        snap.exists ? (snap.data()!['confirmCount'] as int? ?? 0) : 0;

    if (count >= 3) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CoordinatePickerDialog(
        fromMfy: fromMfy,
        toMfy: toMfy,
        driverId: driverId,
        repo: repo,
      ),
    );
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
      backgroundColor: AppColors.moduleBg,
      appBar: AppBar(
        title: Text(c.isRegistered
            ? context.tr('marshrut_route_profile')
            : context.tr('marshrut_route_driver_title')),
        backgroundColor: AppColors.primary,
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Banner(isRegistered: c.isRegistered),
            const SizedBox(height: 20),
            _label(context.tr('marshrut_work_start_time')),
            const SizedBox(height: 8),
            _startTimeTile(c),
            const SizedBox(height: 24),
            _sectionTitle(context.tr('marshrut_route_points')),
            const SizedBox(height: 4),
            Text(context.tr('marshrut_start_end_required'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            _stopLabel(context.tr('marshrut_start_point'), required: true),
            const SizedBox(height: 6),
            MfyField(
              ctrl: _fromCtrl,
              hint: context.tr('mfy_select_hint'),
              iconColor: AppColors.primary,
              showSug: _showFromSug,
              query: _fromQuery,
              onChanged: (q) => setState(() {
                _fromQuery = q;
                _showFromSug = q.length >= 2;
              }),
              onSelected: (v) {
                final normalized = GurlanPlaces.normalizeMfyName(v);
                final err = c.trySetFromMfy(normalized);
                if (err != null) {
                  _snack(context.trMsg(err));
                  return;
                }
                _fromCtrl.text = normalized;
                setState(() => _showFromSug = false);
              },
              onClear: () {
                c.trySetFromMfy('');
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
              hint: context.tr('marshrut_add_mid_stop_hint'),
              iconColor: Colors.blueGrey,
              showSug: _showMidSug,
              query: _midQuery,
              onChanged: (q) => setState(() {
                _midQuery = q;
                _showMidSug = q.length >= 2;
              }),
              onSelected: (v) {
                final normalized = GurlanPlaces.normalizeMfyName(v);
                final err = c.tryAddMidStop(normalized);
                if (err != null) {
                  _snack(context.trMsg(err));
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
            _stopLabel(context.tr('marshrut_end_point'), required: true),
            const SizedBox(height: 6),
            MfyField(
              ctrl: _toCtrl,
              hint: context.tr('mfy_select_hint'),
              iconColor: Colors.red,
              showSug: _showToSug,
              query: _toQuery,
              onChanged: (q) => setState(() {
                _toQuery = q;
                _showToSug = q.length >= 2;
              }),
              onSelected: (v) {
                final normalized = GurlanPlaces.normalizeMfyName(v);
                final err = c.trySetToMfy(normalized);
                if (err != null) {
                  _snack(context.trMsg(err));
                  return;
                }
                _toCtrl.text = normalized;
                setState(() => _showToSug = false);
              },
              onClear: () {
                c.trySetToMfy('');
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

  Widget _startTimeTile(MarshrutRegisterController c) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: c.startTime.hour,
            minute: c.startTime.minute,
          ),
          helpText: context.tr('marshrut_pick_work_start_time'),
          cancelText: context.tr('cancel_search'),
          confirmText: context.tr('time_picker_select'),
        );
        if (picked != null) {
          c.setStartTime(picked.hour, picked.minute);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: _color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.startTimeLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              context.tr('marshrut_queue_from_time'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _midStopsHeader() {
    return Row(children: [
      _stopLabel(context.tr('marshrut_mid_stops_optional'), required: false),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8)),
        child: Text(context.tr('optional_badge'),
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

  void _normalizeControllerRoute(MarshrutRegisterController c) {
    if (c.fromMfy.isNotEmpty) {
      c.trySetFromMfy(GurlanPlaces.normalizeMfyName(c.fromMfy));
    }
    if (c.toMfy.isNotEmpty) {
      c.trySetToMfy(GurlanPlaces.normalizeMfyName(c.toMfy));
    }
    final mids = c.midStops.map(GurlanPlaces.normalizeMfyName).toList();
    for (var i = c.midStops.length - 1; i >= 0; i--) {
      c.removeMidStop(i);
    }
    for (final m in mids) {
      c.tryAddMidStop(m);
    }
  }

  Widget _saveButton(MarshrutRegisterController c) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: (c.isSaving || !c.canSaveRoute)
            ? null
            : () async {
                _normalizeControllerRoute(c);
                await c.save();
              },
        icon: c.isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check_circle, size: 22),
        label: Text(
          c.isSaving
              ? context.tr('saving_in_progress')
              : c.isRegistered
                  ? context.tr('update_and_start')
                  : context.tr('save_and_start'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800));

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
          colors: [AppColors.primaryDark, AppColors.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Text('🚐', style: TextStyle(fontSize: 32)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('marshrut_driver_role_title'),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(
            isRegistered
                ? context.tr('marshrut_update_your_data')
                : context.tr('marshrut_register_once_hint'),
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85)),
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

class _CoordinatePickerDialog extends StatefulWidget {
  const _CoordinatePickerDialog({
    required this.fromMfy,
    required this.toMfy,
    required this.driverId,
    required this.repo,
  });

  final String fromMfy;
  final String toMfy;
  final String driverId;
  final MarshrutDriverRepository repo;

  @override
  State<_CoordinatePickerDialog> createState() =>
      _CoordinatePickerDialogState();
}

class _CoordinatePickerDialogState extends State<_CoordinatePickerDialog> {
  LatLng? _startPoint;
  LatLng? _endPoint;
  bool _pickingStart = true;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(context.tr('mark_route_coordinates')),
      content: SizedBox(
        height: 320,
        child: Column(
          children: [
            Text(
              _pickingStart
                  ? context.tr('mark_start_point')
                  : context.tr('mark_end_point'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(41.6, 60.6),
                  zoom: 13,
                ),
                onTap: (pos) {
                  setState(() {
                    if (_pickingStart) {
                      _startPoint = pos;
                    } else {
                      _endPoint = pos;
                    }
                  });
                },
                markers: {
                  if (_startPoint != null)
                    Marker(
                      markerId: const MarkerId('start'),
                      position: _startPoint!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                    ),
                  if (_endPoint != null)
                    Marker(
                      markerId: const MarkerId('end'),
                      position: _endPoint!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed,
                      ),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('skip')),
        ),
        if (_pickingStart && _startPoint != null)
          ElevatedButton(
            onPressed: () => setState(() => _pickingStart = false),
            child: Text(context.tr('next')),
          ),
        if (!_pickingStart && _endPoint != null)
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('save')),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (_startPoint == null || _endPoint == null) return;
    setState(() => _saving = true);
    await widget.repo.contributeRouteCoordinates(
      from: widget.fromMfy,
      to: widget.toMfy,
      startLat: _startPoint!.latitude,
      startLng: _startPoint!.longitude,
      endLat: _endPoint!.latitude,
      endLng: _endPoint!.longitude,
      driverId: widget.driverId,
    );
    if (mounted) Navigator.pop(context);
  }
}
