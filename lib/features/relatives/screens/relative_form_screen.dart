import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/relative_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../l10n/relatives_l10n.dart';
import '../services/relative_photo_storage.dart';
import '../services/tree_service.dart';
import '../utils/relative_name_smart.dart';

/// Qarindosh qo'shish / tahrirlash.
class RelativeFormScreen extends StatefulWidget {
  const RelativeFormScreen({
    super.key,
    required this.userId,
    this.existing,
    this.allPeople = const [],
  });

  final String userId;
  final RelativePerson? existing;

  /// Nasab bog'lanishi (ota/ona/turmush o'rtog'i) dropdownlari uchun.
  final List<RelativePerson> allPeople;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<RelativeFormScreen> createState() => _RelativeFormScreenState();
}

class _RelativeFormScreenState extends State<RelativeFormScreen> {
  final _repo = RelativesRepository();
  final _photo = RelativePhotoStorage();
  final _picker = ImagePicker();

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _patronymicCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _gender = '';
  String _side = '';
  String _photoUrl = '';
  String _photoPath = '';
  String? _fatherId;
  String? _motherId;
  String? _spouseId;
  bool _busy = false;
  String? _birthError;
  List<({RelativePerson person, double score})> _similar = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final parts = RelativeNameSmart.fromPerson(e);
      _firstCtrl.text = parts.firstName;
      _lastCtrl.text = parts.lastName;
      _patronymicCtrl.text = parts.patronymic;
      _phoneCtrl.text = e.phone;
      _addressCtrl.text = e.address;
      _degreeCtrl.text = e.relationDegree;
      _notesCtrl.text = e.notes;
      if (e.birthDate != null) {
        _birthCtrl.text = _fmtDate(e.birthDate!);
      }
      _gender = e.gender;
      _side = e.side;
      _photoUrl = e.photoUrl;
      _photoPath = e.photoPath;
      _fatherId = e.fatherId;
      _motherId = e.motherId;
      _spouseId = e.spouseId;
    }
    _firstCtrl.addListener(_refreshSimilar);
    _lastCtrl.addListener(_refreshSimilar);
    _patronymicCtrl.addListener(_refreshSimilar);
  }

  @override
  void dispose() {
    _firstCtrl.removeListener(_refreshSimilar);
    _lastCtrl.removeListener(_refreshSimilar);
    _patronymicCtrl.removeListener(_refreshSimilar);
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _patronymicCtrl.dispose();
    _birthCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _degreeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  RelativeNameParts get _queryParts => RelativeNameParts(
        firstName: _firstCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        patronymic: _patronymicCtrl.text.trim(),
      );

  void _refreshSimilar() {
    final q = _queryParts;
    if (q.firstName.isEmpty) {
      if (_similar.isNotEmpty) setState(() => _similar = const []);
      return;
    }
    final found = RelativeNameSmart.findSimilarPeople(
      query: q,
      people: widget.allPeople,
      excludeId: widget.existing?.id,
    );
    setState(() => _similar = found.take(3).toList());
  }

  Future<void> _pickPhoto() async {
    final XFile? file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final res =
          await _photo.uploadPhoto(userId: widget.userId, image: file);
      setState(() {
        _photoUrl = res.url;
        _photoPath = res.path;
      });
    } catch (e) {
      _snack(RelativesL10n.trParams(
          context, 'rel_photo_upload_error', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime? _parseBirthInput() {
    final raw = _birthCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _birthError = null);
      return null;
    }
    final d = parseBirthDate(raw);
    if (d == null) {
      setState(() => _birthError = context.tr('rel_birth_manual_invalid'));
      return null;
    }
    final now = DateTime.now();
    if (d.isAfter(now) || d.year < 1900) {
      setState(() => _birthError = context.tr('rel_birth_manual_invalid'));
      return null;
    }
    setState(() => _birthError = null);
    return d;
  }

  Future<void> _applySuggested(RelativePerson p) async {
    final parts = RelativeNameSmart.fromPerson(p);
    setState(() {
      _firstCtrl.text = parts.firstName;
      _lastCtrl.text = parts.lastName;
      _patronymicCtrl.text = parts.patronymic;
    });
    _refreshSimilar();
  }

  Future<bool> _confirmSimilarGate() async {
    if (_similar.isEmpty) return true;
    final top = _similar.first;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rel_similar_title')),
        content: Text(
          RelativesL10n.trParams(ctx, 'rel_similar_body', {
            'mine': _queryParts.displayFullName,
            'other': top.person.fullName,
            'pct': '${(top.score * 100).round()}',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: Text(ctx.tr('rel_similar_keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fix'),
            child: Text(ctx.tr('rel_similar_fix')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: Text(ctx.tr('rel_similar_merge')),
          ),
        ],
      ),
    );
    if (action == null) return false;
    if (action == 'fix') {
      await _applySuggested(top.person);
      return false;
    }
    if (action == 'merge') {
      await _mergeInto(top.person);
      return false;
    }
    return true; // keep — янги deb сақлаш
  }

  Future<void> _mergeInto(RelativePerson existing) async {
    setState(() => _busy = true);
    try {
      final birth = _parseBirthInput();
      if (_birthCtrl.text.trim().isNotEmpty && birth == null) return;

      final parts = RelativeNameSmart.fromPerson(existing);
      final composed = RelativeNameSmart.compose(
        firstName: parts.firstName.isNotEmpty
            ? parts.firstName
            : _firstCtrl.text.trim(),
        lastName:
            parts.lastName.isNotEmpty ? parts.lastName : _lastCtrl.text.trim(),
        patronymic: parts.patronymic.isNotEmpty
            ? parts.patronymic
            : _patronymicCtrl.text.trim(),
      );
      final merged = existing.copyWith(
        fullName: composed,
        firstName: parts.firstName.isNotEmpty
            ? parts.firstName
            : _firstCtrl.text.trim(),
        lastName:
            parts.lastName.isNotEmpty ? parts.lastName : _lastCtrl.text.trim(),
        patronymic: parts.patronymic.isNotEmpty
            ? parts.patronymic
            : _patronymicCtrl.text.trim(),
        phone: existing.phone.isNotEmpty
            ? existing.phone
            : _phoneCtrl.text.trim(),
        address: existing.address.isNotEmpty
            ? existing.address
            : _addressCtrl.text.trim(),
        birthDate: existing.birthDate ?? birth,
        gender: existing.gender.isNotEmpty ? existing.gender : _gender,
        relationDegree: existing.relationDegree.isNotEmpty
            ? existing.relationDegree
            : _degreeCtrl.text.trim(),
        side: existing.side.isNotEmpty ? existing.side : _side,
        notes: existing.notes.isNotEmpty
            ? existing.notes
            : _notesCtrl.text.trim(),
        photoUrl: existing.photoUrl.isNotEmpty ? existing.photoUrl : _photoUrl,
        photoPath:
            existing.photoPath.isNotEmpty ? existing.photoPath : _photoPath,
        fatherId: existing.fatherId ?? _fatherId,
        motherId: existing.motherId ?? _motherId,
        spouseId: existing.spouseId ?? _spouseId,
      );
      await _persistOwnedPerson(merged);
      if (widget.existing != null &&
          widget.existing!.id != existing.id &&
          !(widget.existing!.isSelf)) {
        // Янги форма эди — эски duplicate йўқ; editда бошқасига merge
      }
      if (mounted) {
        _snack(context.tr('rel_similar_merged_ok'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _snack(_errMsg(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Genealogy → CF saveTreeNode; CRM → client merge (тарих сақланади).
  Future<void> _persistOwnedPerson(RelativePerson person) async {
    await TreeService.saveNode(
      nodeId: person.id,
      fullName: person.fullName,
      firstName: person.firstName,
      lastName: person.lastName,
      patronymic: person.patronymic,
      gender: person.gender,
      photoUrl: person.photoUrl,
      photoPath: person.photoPath,
      birthDate: person.birthDate,
      fatherId: person.fatherId,
      motherId: person.motherId,
      spouseId: person.spouseId,
    );
    await _repo.updatePersonCrm(
      widget.userId,
      person.id,
      phone: person.phone,
      address: person.address,
      relationDegree: person.relationDegree,
      side: person.side,
      notes: person.notes,
    );
  }

  String _errMsg(Object e) {
    if (e is FirebaseFunctionsException) {
      return firebaseFunctionsUserMessage(e);
    }
    return RelativesL10n.trParams(context, 'error_generic', {'error': '$e'});
  }

  Future<void> _save() async {
    final isSelf = widget.existing?.isSelf ?? false;
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (!isSelf) {
      if (first.isEmpty) {
        _snack(context.tr('rel_first_name_required'));
        return;
      }
      if (last.isEmpty) {
        _snack(context.tr('rel_last_name_required'));
        return;
      }
    }

    final birth = isSelf ? widget.existing?.birthDate : _parseBirthInput();
    if (!isSelf && _birthCtrl.text.trim().isNotEmpty && birth == null) {
      return;
    }

    if (!isSelf) {
      final ok = await _confirmSimilarGate();
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final patronymic = _patronymicCtrl.text.trim();
      final composed = isSelf
          ? existing!.fullName
          : RelativeNameSmart.compose(
              firstName: first,
              lastName: last,
              patronymic: patronymic,
            );
      final person = RelativePerson(
        id: existing?.id ?? '',
        fullName: composed,
        firstName: isSelf ? existing!.firstName : first,
        lastName: isSelf ? existing!.lastName : last,
        patronymic: isSelf ? existing!.patronymic : patronymic,
        photoUrl: isSelf ? existing!.photoUrl : _photoUrl,
        photoPath: isSelf ? existing!.photoPath : _photoPath,
        phone: isSelf ? existing!.phone : _phoneCtrl.text.trim(),
        address: isSelf ? existing!.address : _addressCtrl.text.trim(),
        birthDate: birth,
        gender: isSelf ? existing!.gender : _gender,
        relationDegree:
            isSelf ? existing!.relationDegree : _degreeCtrl.text.trim(),
        side: _side,
        notes: _notesCtrl.text.trim(),
        fatherId: _fatherId,
        motherId: _motherId,
        spouseId: _spouseId,
        isSelf: isSelf,
      );
      if (widget.existing == null) {
        await _repo.addPerson(widget.userId, person);
      } else {
        await _persistOwnedPerson(person);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _snack(_errMsg(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isSelf = widget.existing?.isSelf ?? false;
    final title = isSelf
        ? context.tr('rel_me')
        : (isEdit
            ? context.tr('edit')
            : context.tr('rel_form_add_title'));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: RelativeFormScreen._accent,
          foregroundColor: Colors.white,
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: context.tr('rel_tab_personal')),
              Tab(text: context.tr('rel_tab_nasab')),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _personalTabChildren(isSelf),
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: _nasabTabChildren(),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RelativeFormScreen._accent,
                      foregroundColor: Colors.white,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.tr('save')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _personalTabChildren(bool isSelf) {
    return [
      if (isSelf)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: RelativeFormScreen._accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.tr('rel_form_self_hint'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
      if (!isSelf)
        Center(
          child: GestureDetector(
            onTap: _busy ? null : _pickPhoto,
            child: CircleAvatar(
              radius: 44,
              backgroundColor:
                  RelativeFormScreen._accent.withValues(alpha: 0.12),
              backgroundImage:
                  _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
              child: _photoUrl.isEmpty
                  ? const Icon(Icons.add_a_photo_outlined,
                      color: RelativeFormScreen._accent)
                  : null,
            ),
          ),
        ),
      if (!isSelf) const SizedBox(height: 16),
      if (isSelf)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor:
                RelativeFormScreen._accent.withValues(alpha: 0.12),
            backgroundImage:
                _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
            child: _photoUrl.isEmpty
                ? const Icon(Icons.person, color: RelativeFormScreen._accent)
                : null,
          ),
          title: Text(
            RelativeNameSmart.compose(
              firstName: _firstCtrl.text,
              lastName: _lastCtrl.text,
              patronymic: _patronymicCtrl.text,
            ).isNotEmpty
                ? RelativeNameSmart.compose(
                    firstName: _firstCtrl.text,
                    lastName: _lastCtrl.text,
                    patronymic: _patronymicCtrl.text,
                  )
                : widget.existing!.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text([
            if (_phoneCtrl.text.isNotEmpty) _phoneCtrl.text,
            if (_birthCtrl.text.isNotEmpty) _birthCtrl.text,
          ].join(' · ')),
        ),
      if (!isSelf) ...[
        _field(_firstCtrl, context.tr('rel_field_first_name'),
            Icons.badge_outlined),
        _field(_lastCtrl, context.tr('rel_field_last_name'),
            Icons.family_restroom_outlined),
        _field(_patronymicCtrl, context.tr('rel_field_patronymic'),
            Icons.person_outline),
        if (_similar.isNotEmpty) _similarBanner(),
        _field(_phoneCtrl, context.tr('phone'), Icons.phone_outlined,
            keyboard: TextInputType.phone),
        _field(_degreeCtrl, context.tr('rel_field_degree'),
            Icons.diversity_1_outlined),
        _field(_addressCtrl, context.tr('rel_field_address'),
            Icons.location_on_outlined),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _birthCtrl,
            keyboardType: TextInputType.datetime,
            onChanged: (_) {
              if (_birthError != null) _parseBirthInput();
            },
            decoration: InputDecoration(
              labelText: context.tr('rel_field_birth_manual'),
              hintText: context.tr('rel_birth_manual_hint'),
              prefixIcon: const Icon(Icons.cake_outlined),
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _birthError,
              helperText: context.tr('rel_birth_manual_helper'),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _dropdown(
          context.tr('rel_field_gender'),
          _gender,
          RelativesL10n.genderOptions(context),
          (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: 12),
      ],
      _dropdown(
        context.tr('rel_field_side'),
        _side,
        RelativesL10n.sideOptions(context),
        (v) => setState(() => _side = v),
      ),
      const SizedBox(height: 12),
      _field(_notesCtrl, context.tr('rel_field_notes'), Icons.notes_outlined,
          maxLines: 3),
    ];
  }

  List<Widget> _nasabTabChildren() {
    if (_others.isEmpty) {
      return [
        Text(
          context.tr('rel_nasab_need_people'),
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
      ];
    }
    return [
      Text(
        context.tr('rel_tree_links_section'),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: RelativeFormScreen._accent,
        ),
      ),
      const SizedBox(height: 12),
      _relativeDropdown(context.tr('rel_father'), _fatherId,
          (v) => setState(() => _fatherId = v)),
      const SizedBox(height: 12),
      _relativeDropdown(context.tr('rel_mother'), _motherId,
          (v) => setState(() => _motherId = v)),
      const SizedBox(height: 12),
      _relativeDropdown(context.tr('rel_spouse'), _spouseId,
          (v) => setState(() => _spouseId = v)),
    ];
  }

  Widget _similarBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('rel_similar_hint'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFFE65100),
                ),
              ),
              const SizedBox(height: 6),
              for (final s in _similar)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.person.fullName),
                  subtitle: Text('${(s.score * 100).round()}%'),
                  trailing: TextButton(
                    onPressed: () => _applySuggested(s.person),
                    child: Text(context.tr('rel_similar_fix')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: options.entries
              .map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }

  List<RelativePerson> get _others {
    final selfId = widget.existing?.id;
    return widget.allPeople.where((p) => p.id != selfId).toList();
  }

  String _linkLabel(RelativePerson p) {
    final parts = <String>[p.fullName];
    if (p.birthDate != null) parts.add(_fmtDate(p.birthDate!));
    if (p.relationDegree.isNotEmpty) parts.add(p.relationDegree);
    return parts.join(' · ');
  }

  Widget _relativeDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    final exists = value != null && _others.any((p) => p.id == value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.account_tree_outlined),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: exists ? value : null,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
                value: null, child: Text(context.tr('rel_link_none'))),
            ..._others.map((p) => DropdownMenuItem<String?>(
                  value: p.id,
                  child: Text(_linkLabel(p), overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _fmtDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }
}
