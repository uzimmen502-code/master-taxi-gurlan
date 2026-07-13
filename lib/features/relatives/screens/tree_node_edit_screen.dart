import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/tree_person.dart';
import '../l10n/relatives_l10n.dart';
import '../services/relative_photo_storage.dart';
import '../services/tree_service.dart';
import '../utils/relative_name_smart.dart';

/// Umumiy nasab tugunini yaratish/tahrirlash (Faza 5 — umumiy tahrir).
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
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _patronymicCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();

  String _gender = '';
  String _photoUrl = '';
  String _photoPath = '';
  String? _fatherId;
  String? _motherId;
  String? _spouseId;
  bool _busy = false;
  String? _birthError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final parts = RelativeNameSmart.splitLegacy(e.fullName);
      _firstCtrl.text = parts.firstName;
      _lastCtrl.text = parts.lastName;
      _patronymicCtrl.text = parts.patronymic;
      if (e.birthDate != null) {
        _birthCtrl.text = _fmtDate(e.birthDate!);
      }
      _gender = e.gender;
      _photoUrl = e.photoUrl;
      _fatherId = e.fatherId;
      _motherId = e.motherId;
      _spouseId = e.spouseId;
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _patronymicCtrl.dispose();
    _birthCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _save() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty) {
      _snack(context.tr('rel_first_name_required'));
      return;
    }
    if (last.isEmpty) {
      _snack(context.tr('rel_last_name_required'));
      return;
    }
    final birth = _parseBirthInput();
    if (_birthCtrl.text.trim().isNotEmpty && birth == null) return;

    final patronymic = _patronymicCtrl.text.trim();
    final name = RelativeNameSmart.compose(
      firstName: first,
      lastName: last,
      patronymic: patronymic,
    );

    setState(() => _busy = true);
    try {
      if (widget.existing == null) {
        await TreeService.addRelativePerson(
          fullName: name,
          firstName: first,
          lastName: last,
          patronymic: patronymic,
          gender: _gender,
          photoUrl: _photoUrl,
          photoPath: _photoPath,
          birthDate: birth,
          fatherId: _fatherId,
          motherId: _motherId,
          spouseId: _spouseId,
        );
      } else {
        await TreeService.saveNode(
          nodeId: widget.existing!.id,
          fullName: name,
          firstName: first,
          lastName: last,
          patronymic: patronymic,
          gender: _gender,
          photoUrl: _photoUrl,
          photoPath: _photoPath,
          birthDate: birth,
          fatherId: _fatherId,
          motherId: _motherId,
          spouseId: _spouseId,
        );
      }
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack(RelativesL10n.trParams(
          context, 'error_generic', {'error': '$e'}));
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
        title: Text(isEdit
            ? context.tr('rel_node_edit_title')
            : context.tr('rel_node_add_title')),
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
          _field(_firstCtrl, context.tr('rel_field_first_name'),
              Icons.badge_outlined),
          _field(_lastCtrl, context.tr('rel_field_last_name'),
              Icons.family_restroom_outlined),
          _field(_patronymicCtrl, context.tr('rel_field_patronymic'),
              Icons.person_outline),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _birthCtrl,
              keyboardType: TextInputType.datetime,
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
          _dropdown(
            context.tr('rel_field_gender'),
            _gender,
            RelativesL10n.genderOptions(context),
            (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              context.tr('rel_tree_links_section'),
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: TreeNodeEditScreen._accent),
            ),
          ),
          _relativeDropdown(context.tr('rel_father'), _fatherId,
              (v) => setState(() => _fatherId = v)),
          const SizedBox(height: 12),
          _relativeDropdown(context.tr('rel_mother'), _motherId,
              (v) => setState(() => _motherId = v)),
          const SizedBox(height: 12),
          _relativeDropdown(context.tr('rel_spouse'), _spouseId,
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
                  : Text(context.tr('save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
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

  String _nodeLinkLabel(TreePerson p) {
    final parts = <String>[p.fullName];
    if (p.birthDate != null) parts.add(_fmtDate(p.birthDate!));
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
                  child: Text(_nodeLinkLabel(p), overflow: TextOverflow.ellipsis),
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
