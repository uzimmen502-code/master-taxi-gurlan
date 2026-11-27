import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/job_ad_service.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../jobs/controllers/jobs_controller.dart';
import '../domain/job_vacancy.dart';

/// Янги вакансия (эга 2026-11-28): лавозим, маош (бутун сўм: дан/гача ёки «Келишилади»), иш тартиби, тажриба,
/// иш берувчи (ўз бизнес объекти — ихтиёрий; завод ҳам шу) ва МАЖБУРИЙ «Талаблар». Юбориш — мавжуд
/// `submitJobAd` (type `work` + `vacancy`); модерация/авто-тасдиқ — `jobs` билан бир хил.
class VacancyFormScreen extends StatefulWidget {
  const VacancyFormScreen({super.key, this.employerBusinessId = '', this.loadMyBusinesses, this.submit});

  /// Завод саҳифасидан «Вакансия қўшиш» — шу объект олдиндан танланган.
  final String employerBusinessId;

  @visibleForTesting
  final Future<List<Business>> Function()? loadMyBusinesses;

  /// Тест учун: сервер чақируви ўрнига → `status`.
  @visibleForTesting
  final Future<String> Function(Map<String, Object?> vacancy, String text, String requestId)? submit;

  @override
  State<VacancyFormScreen> createState() => _VacancyFormScreenState();
}

class _VacancyFormScreenState extends State<VacancyFormScreen> {
  final _position = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _requirements = TextEditingController();
  final _description = TextEditingController();
  bool _negotiable = false;
  String _schedule = JobVacancy.schedules.first;
  String _experience = JobVacancy.experiences.first;
  String _employerId = '';
  List<Business> _mine = const [];
  bool _busy = false;
  String? _error;

  /// Бир марта: тармоқ узилиб қайта босилса — вакансия такрорланмайди (сервер idempotent).
  final String _seed = JobsController.newRequestSeed();

  @override
  void initState() {
    super.initState();
    _employerId = widget.employerBusinessId;
    _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final custom = widget.loadMyBusinesses;
      final List<Business> list;
      if (custom != null) {
        list = await custom();
      } else {
        final uid = canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
        list = uid.length >= 12 ? await BusinessRepository().fetchByOwner(uid) : const <Business>[];
      }
      if (!mounted) return;
      setState(() {
        _mine = [for (final b in list) if (!b.isBlocked) b];
        if (_employerId.isNotEmpty && !_mine.any((b) => b.id == _employerId)) _employerId = '';
      });
    } catch (e) {
      debugPrint('[VacancyForm] VACANCY_EMPLOYERS_LOAD_FAILED: $e');
    }
  }

  @override
  void dispose() {
    for (final c in [_position, _from, _to, _requirements, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final err = JobVacancy.validate(
      position: _position.text,
      requirements: _requirements.text,
      negotiable: _negotiable,
      fromRaw: _from.text,
      toRaw: _to.text,
      schedule: _schedule,
      experience: _experience,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Business? employer;
    for (final b in _mine) {
      if (b.id == _employerId) employer = b;
    }
    final payload = JobVacancy.payload(
      position: _position.text,
      requirements: _requirements.text,
      negotiable: _negotiable,
      salaryFrom: JobVacancy.parseSalary(_from.text),
      salaryTo: JobVacancy.parseSalary(_to.text),
      schedule: _schedule,
      experience: _experience,
      // Иш жойи — танланган объект тумани (бўлмаса сервер профил ҳудудини олади).
      districtId: employer?.districtId ?? '',
      employerKind: employer == null ? '' : 'business',
      employerId: employer?.id ?? '',
    );
    final text = _description.text.trim();
    final requestId = '$_seed-${(Object.hashAll([payload.toString(), text]) & 0x7fffffff).toRadixString(36)}';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await (widget.submit?.call(payload, text, requestId) ??
          JobAdService.submitAd(type: 'work', text: text, title: _position.text.trim(), vacancy: payload, requestId: requestId)
              .then((r) => r.status));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr(status == 'active' ? 'vac_posted_live' : 'vac_posted_review')),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[VacancyForm] submit: $e');
      String key = 'vac_err_generic';
      if (e is FirebaseFunctionsException) {
        final d = e.details;
        final code = d is Map ? d['code']?.toString() : null;
        key = vacancyErrorKey(code) ?? jobsErrorKey(e, fallback: 'vac_err_generic');
      }
      if (mounted) setState(() => _error = key);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    InputDecoration deco(String labelKey, {String? hintKey}) => InputDecoration(
          labelText: context.tr(labelKey),
          hintText: hintKey == null ? null : context.tr(hintKey),
          border: const OutlineInputBorder(),
        );
    const gap = SizedBox(height: 12);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('vac_form_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            key: const ValueKey('vac_f_position'),
            controller: _position,
            maxLength: JobVacancy.positionMax,
            decoration: deco('vac_field_position', hintKey: 'vac_hint_position'),
          ),
          SwitchListTile(
            key: const ValueKey('vac_f_negotiable'),
            contentPadding: EdgeInsets.zero,
            value: _negotiable,
            onChanged: (v) => setState(() => _negotiable = v),
            title: Text(context.tr('vac_salary_negotiable')),
          ),
          if (!_negotiable)
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('vac_f_from'),
                  controller: _from,
                  keyboardType: TextInputType.number,
                  decoration: deco('vac_field_salary_from'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('vac_f_to'),
                  controller: _to,
                  keyboardType: TextInputType.number,
                  decoration: deco('vac_field_salary_to'),
                ),
              ),
            ]),
          gap,
          DropdownButtonFormField<String>(
            key: const ValueKey('vac_f_schedule'),
            initialValue: _schedule,
            decoration: deco('vac_field_schedule'),
            items: [
              for (final s in JobVacancy.schedules)
                DropdownMenuItem(value: s, child: Text(context.tr(JobVacancy.scheduleKey(s)))),
            ],
            onChanged: (v) => setState(() => _schedule = v ?? _schedule),
          ),
          gap,
          DropdownButtonFormField<String>(
            key: const ValueKey('vac_f_experience'),
            initialValue: _experience,
            decoration: deco('vac_field_experience'),
            items: [
              for (final e in JobVacancy.experiences)
                DropdownMenuItem(value: e, child: Text(context.tr(JobVacancy.experienceKey(e)))),
            ],
            onChanged: (v) => setState(() => _experience = v ?? _experience),
          ),
          if (_mine.isNotEmpty) ...[
            gap,
            DropdownButtonFormField<String>(
              key: const ValueKey('vac_f_employer'),
              initialValue: _employerId,
              decoration: deco('vac_field_employer'),
              items: [
                DropdownMenuItem(value: '', child: Text(context.tr('vac_employer_none'))),
                for (final b in _mine) DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _employerId = v ?? ''),
            ),
          ],
          gap,
          TextField(
            key: const ValueKey('vac_f_requirements'),
            controller: _requirements,
            minLines: 3,
            maxLines: 8,
            maxLength: JobVacancy.requirementsMax,
            decoration: deco('vac_field_requirements', hintKey: 'vac_hint_requirements'),
          ),
          TextField(
            key: const ValueKey('vac_f_description'),
            controller: _description,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: deco('vac_field_description', hintKey: 'vac_hint_description'),
          ),
          if (_error != null) ...[
            Text(context.trMsg(_error!), key: const ValueKey('vac_f_error'), style: TextStyle(color: c.danger)),
            gap,
          ],
          FilledButton(
            key: const ValueKey('vac_f_submit'),
            onPressed: _busy ? null : _send,
            child: Text(context.tr('vac_submit')),
          ),
        ],
      ),
    );
  }
}
