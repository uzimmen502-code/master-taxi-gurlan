import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/tree_person.dart';
import '../services/relative_photo_storage.dart';
import '../services/tree_service.dart';

/// Umumiy nasab tugunini yaratish/tahrirlash (Faza 5 — umumiy tahrir).
/// tree_persons'ga yoziladi; tarmoqdagi har bir a'zo ko'radi.
class TreeNodeEditScreen extends StatefulWidget {
  const TreeNodeEditScreen({
    super.key,
    required this.userId,
    required this.componentNodes,
    this.existing,
  });

  final String userId;
  final List<TreePerson> componentNodes;
  final TreePerson? existing;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<TreeNodeEditScreen> createState() => _TreeNodeEditScreenState();
}

class _TreeNodeEditScreenState extends State<TreeNodeEditScreen> {
  final _photo = RelativePhotoStorage();
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();

  DateTime? _birthDate;
  String _gender = '';
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
      _birthDate = e.birthDate;
      _gender = e.gender;
      _photoUrl = e.photoUrl;
      _fatherId = e.fatherId;
      _motherId = e.motherId;
      _spouseId = e.spouseId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// O'zidan boshqa komponent tugunlari (bog'lanish dropdownlari uchun).
  List<TreePerson> get _others {
    final selfId = widget.existing?.id;
    return widget.componentNodes
        .where((p) => p.id != selfId)
        .toList(growable: false);
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
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Исм-фамилияни киритинг.');
      return;
    }
    setState(() => _busy = true);
    try {
      await TreeService.saveNode(
        nodeId: widget.existing?.id ?? '',
        fullName: name,
        gender: _gender,
        photoUrl: _photoUrl,
        photoPath: _photoPath,
        birthDate: _birthDate,
        fatherId: _fatherId,
        motherId: _motherId,
        spouseId: _spouseId,
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack('Хатолик: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Тугунни таҳрирлаш' : 'Янги аъзо қўшиш'),
        backgroundColor: TreeNodeEditScreen._accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pickPhoto,
              child: CircleAvatar(
                radius: 44,
                backgroundColor:
                    TreeNodeEditScreen._accent.withValues(alpha: 0.12),
                backgroundImage:
                    _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
                child: _photoUrl.isEmpty
                    ? const Icon(Icons.add_a_photo_outlined,
                        color: TreeNodeEditScreen._accent)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Исм-фамилия *',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cake_outlined),
            title: Text(
                _birthDate == null ? 'Туғилган сана' : _fmtDate(_birthDate!)),
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
          const SizedBox(height: 8),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('🌳 Насаб боғланиши',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: TreeNodeEditScreen._accent)),
          ),
          _relativeDropdown(
              'Отаси', _fatherId, (v) => setState(() => _fatherId = v)),
          const SizedBox(height: 12),
          _relativeDropdown(
              'Онаси', _motherId, (v) => setState(() => _motherId = v)),
          const SizedBox(height: 12),
          _relativeDropdown('Турмуш ўртоғи', _spouseId,
              (v) => setState(() => _spouseId = v)),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: TreeNodeEditScreen._accent,
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
                  child: Text(p.fullName, overflow: TextOverflow.ellipsis),
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
