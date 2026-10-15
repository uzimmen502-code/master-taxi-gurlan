// ПРОФИЛДА КУРЬЕРЛИК — «Курьер бўлиш» аризаси ва «Курьер панели»
// (D-15.5, эга қарори 2026-10-08).
//
// Ҳуқуқ — `provider_capabilities.status.courier` (D-12, D-CLEAN-1), эски
// `users.role` эмас. Шу сабабли админ қўшган курьер ҳам панелни кўради
// (аввал фақат яширин PIN орқали кирарди).
//
//   not_registered → «Курьер бўлиш» → `requestCapability`:
//                    Мануал — `applied` (админ тасдиғигача иш йўқ),
//                    Авто — дарҳол `approved` (D-15.3).
//   applied        → «Аризангиз кўриб чиқилмоқда».
//   trial…approved → «Курьер панели».
//   suspended / document_rejected → панел (қўлдаги ишни тугатиш, D-15.4)
//                    + огоҳлантириш.
//
// Ҳолат профил очилганда БИР МАРТА ўқилади (listener йўқ, 36-қоида).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/courier_capability_repository.dart';
import '../screens/courier_screen.dart';
import 'courier_apply_flow.dart';

/// Профилдаги роль тугмаси (`_rolePanelButton`) — кўриниш бир хил бўлсин.
typedef ProfilePanelButtonBuilder = Widget Function({
  required String label,
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
});

class CourierProfileEntry extends StatefulWidget {
  const CourierProfileEntry({
    super.key,
    required this.userId,
    required this.legacyCourierRole,
    required this.panelButton,
    this.repository,
  });

  /// Канон телефон ID (`998XXXXXXXXX`).
  final String userId;

  /// Эски локал `user_role == 'courier'` (PIN). Ўтиш даврида панел
  /// аввалгидек кўринади; серверда ҳуқуқ барибир capability'дан.
  final bool legacyCourierRole;

  final ProfilePanelButtonBuilder panelButton;
  final CourierCapabilityRepository? repository;

  @override
  State<CourierProfileEntry> createState() => _CourierProfileEntryState();
}

class _CourierProfileEntryState extends State<CourierProfileEntry> {
  late final CourierCapabilityRepository _repo;

  /// `null` — ҳали юкланмоқда ёки ўқиб бўлмади.
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? CourierCapabilityRepository();
    _load();
  }

  @override
  void didUpdateWidget(CourierProfileEntry old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.fetchStatus(widget.userId);
      if (mounted) setState(() => _status = s);
    } catch (e) {
      // Ўқиб бўлмаса ариза тугмаси кўрсатилмайди (нотўғри ҳолатда
      // таклиф қилмаймиз); эски PIN панели барибир ишлайди.
      debugPrint('courier_profile_entry.load: $e');
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await runCourierApplyFlow(context, repository: _repo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.status != null && r.status!.isNotEmpty) _status = r.status;
    });
    if (r.failed) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final showPanel = widget.legacyCourierRole ||
        (s != null && CourierCapabilityRepository.panelStatuses.contains(s));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPanel)
          widget.panelButton(
            label: context.tr('profile_courier_panel'),
            icon: Icons.delivery_dining,
            color: AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CourierScreen()),
            ),
          ),
        if (s != null &&
            CourierCapabilityRepository.finishOnlyStatuses.contains(s))
          _note(Icons.info_outline, context.tr('courier_suspended_note'),
              Colors.red.shade700),
        if (s == CourierCapabilityRepository.applied)
          _note(Icons.hourglass_top_rounded,
              context.tr('courier_apply_pending'), AppColors.primaryMid),
        if (s == CourierCapabilityRepository.notRegistered &&
            !widget.legacyCourierRole)
          widget.panelButton(
            label: context.tr('courier_apply_button'),
            icon: _busy ? Icons.hourglass_top_rounded : Icons.delivery_dining,
            color: AppColors.primaryMid,
            onTap: _apply,
          ),
      ],
    );
  }

  Widget _note(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}
