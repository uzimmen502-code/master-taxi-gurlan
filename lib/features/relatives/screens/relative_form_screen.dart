import 'package:flutter/material.dart';

import '../../../models/relative_person.dart';
import '../../../repositories/relatives_repository.dart';
import 'package:image_picker/image_picker.dart';
import '../services/relative_photo_storage.dart';

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

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _birthDate;
  String _gender = '';
  String _side = '';
  String _photoUrl = '';
  String _photoPath = '';
  String? _fatherId;
  String? _motherId;
  String? _spouseId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.fullName;
      _phoneCtrl.text = e.phone;
      _addressCtrl.text = e.address;
      _degreeCtrl.text = e.relationDegree;
      _notesCtrl.text = e.notes;
      _birthDate = e.birthDate;
      _gender = e.gender;
      _side = e.side;
      _photoUrl = e.photoUrl;
      _photoPath = e.photoPath;
      _fatherId = e.fatherId;
      _motherId = e.motherId;
      _spouseId = e.spouseId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _degreeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
      _snack('Расм юклашда хатолик: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (d != null) setState(() => _birthDate = d);
  }

  Future<void> _save() async {
    final isSelf = widget.existing?.isSelf ?? false;
    final name = _nameCtrl.text.trim();
    if (!isSelf && name.isEmpty) {
      _snack('Исм-фамилияни киритинг.');
      return;
    }
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final person = RelativePerson(
        id: existing?.id ?? '',
        fullName: isSelf ? existing!.fullName : name,
        photoUrl: isSelf ? existing!.photoUrl : _photoUrl,
        photoPath: isSelf ? existing!.photoPath : _photoPath,
        phone: isSelf ? existing!.phone : _phoneCtrl.text.trim(),
        address: isSelf ? existing!.address : _addressCtrl.text.trim(),
        birthDate: isSelf ? existing!.birthDate : _birthDate,
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
        await _repo.updatePerson(widget.userId, widget.existing!.id, person);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('Хатолик: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(isSelf ? 'Мен' : (isEdit ? 'Таҳрирлаш' : 'Қариндош қўшиш')),
        backgroundColor: RelativeFormScreen._accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isSelf)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: RelativeFormScreen._accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Исм, телефон, манзил ва туғилган сана профилингиздан '
                    'автомат синхронланади. Бу ерда насаб боғланишларини '
                    'танлашингиз мумкин.',
                    style: TextStyle(fontSize: 13),
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
              title: Text(_nameCtrl.text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                if (_phoneCtrl.text.isNotEmpty) _phoneCtrl.text,
                if (_birthDate != null) _fmtDate(_birthDate!),
              ].join(' · ')),
            ),
          if (!isSelf) ...[
            _field(_nameCtrl, 'Исм-фамилия *', Icons.person_outline),
            _field(_phoneCtrl, 'Телефон', Icons.phone_outlined,
                keyboard: TextInputType.phone),
            _field(_degreeCtrl, 'Қариндошлик даражаси (масалан: амаки)',
                Icons.diversity_1_outlined),
            _field(_addressCtrl, 'Манзил', Icons.location_on_outlined),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cake_outlined),
              title: Text(_birthDate == null
                  ? 'Туғилган сана'
                  : _fmtDate(_birthDate!)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickBirthDate,
            ),
            const SizedBox(height: 8),
            _dropdown(
              'Жинс',
              _gender,
              const {'': 'Танланмаган', 'male': 'Эркак', 'female': 'Аёл'},
              (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 12),
          ],
          _dropdown(
            'Томон',
            _side,
            const {
              '': 'Танланмаган',
              'paternal': 'Ота томон',
              'maternal': 'Она томон'
            },
            (v) => setState(() => _side = v),
          ),
          const SizedBox(height: 12),
          _field(_notesCtrl, 'Изоҳ', Icons.notes_outlined, maxLines: 3),
          if (_others.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('🌳 Насаб боғланиши',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: RelativeFormScreen._accent)),
            ),
            _relativeDropdown('Отаси', _fatherId,
                (v) => setState(() => _fatherId = v)),
            const SizedBox(height: 12),
            _relativeDropdown('Онаси', _motherId,
                (v) => setState(() => _motherId = v)),
            const SizedBox(height: 12),
            _relativeDropdown('Турмуш ўртоғи', _spouseId,
                (v) => setState(() => _spouseId = v)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: RelativeFormScreen._accent,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Сақлаш'),
            ),
          ),
        ],
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

  /// O'zidan boshqa qarindoshlar (bog'lanish dropdownlari uchun).
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
            const DropdownMenuItem<String?>(
                value: null, child: Text('— йўқ —')),
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
