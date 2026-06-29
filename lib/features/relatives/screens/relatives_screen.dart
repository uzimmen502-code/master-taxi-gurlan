import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/relative_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../services/relative_photo_storage.dart';
import 'relative_form_screen.dart';

/// 👨‍👩‍👧 Qarindoshlarim — shaxsiy ro'yxat + tug'ilgan kunlar.
class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

  static const _accent = Color(0xFF6A4C93);

  @override
  State<RelativesScreen> createState() => _RelativesScreenState();
}

class _RelativesScreenState extends State<RelativesScreen> {
  final _repo = RelativesRepository();
  final _photo = RelativePhotoStorage();
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _phone = phone);
  }

  Future<void> _add() async {
    final phone = _phone;
    if (phone == null || phone.length < 12) {
      _snack('Аввал профилда телефонни тасдиқланг.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RelativeFormScreen(userId: phone)),
    );
  }

  Future<void> _edit(RelativePerson p) async {
    final phone = _phone!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelativeFormScreen(userId: phone, existing: p),
      ),
    );
  }

  Future<void> _delete(RelativePerson p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш'),
        content: Text('«${p.fullName}» ни ўчирасизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ўчираман'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deletePerson(_phone!, p.id);
    if (p.photoUrl.isNotEmpty) await _photo.deleteByUrl(p.photoUrl);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4F8),
        appBar: AppBar(
          title: const Text('Қариндошларим'),
          backgroundColor: RelativesScreen._accent,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Рўйхат'),
              Tab(text: '🎂 Туғилган кунлар'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: RelativesScreen._accent,
          foregroundColor: Colors.white,
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Қариндош'),
        ),
        body: phone == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<List<RelativePerson>>(
                stream: _repo.watchPeople(phone),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final people = snap.data ?? const <RelativePerson>[];
                  return TabBarView(
                    children: [
                      _listTab(people),
                      _birthdaysTab(_repo.upcomingBirthdays(people)),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _listTab(List<RelativePerson> people) {
    if (people.isEmpty) {
      return _empty('Ҳали қариндош қўшмагансиз.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: people.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _personTile(people[i]),
    );
  }

  Widget _personTile(RelativePerson p) {
    final sub = [
      if (p.relationDegree.isNotEmpty) p.relationDegree,
      _sideLabel(p.side),
      if (p.age != null) '${p.age} ёш',
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      leading: _avatar(p),
      title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub.isEmpty ? null : Text(sub),
      onTap: () => _edit(p),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () => callPhone(p.phone),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _edit(p);
              if (v == 'delete') _delete(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Таҳрирлаш')),
              PopupMenuItem(value: 'delete', child: Text('Ўчириш')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _birthdaysTab(List<RelativePerson> people) {
    if (people.isEmpty) {
      return _empty('Туғилган санаси киритилган қариндош йўқ.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: people.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = people[i];
        final days = p.daysUntilBirthday ?? 0;
        final nb = p.nextBirthday;
        final turning = (p.age ?? 0) + (days == 0 ? 0 : 1);
        return ListTile(
          leading: _avatar(p),
          title: Text(p.fullName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(nb == null
              ? ''
              : '${_fmtDay(nb)} · $turning ёшга тўлади'),
          trailing: _daysBadge(days),
        );
      },
    );
  }

  Widget _daysBadge(int days) {
    final label = days == 0 ? 'Бугун!' : '$days кун';
    final color = days == 0
        ? Colors.red
        : (days <= 7 ? Colors.orange : RelativesScreen._accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _avatar(RelativePerson p) {
    return CircleAvatar(
      backgroundColor: RelativesScreen._accent.withValues(alpha: 0.15),
      backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
      child: p.photoUrl.isEmpty
          ? Text(
              p.fullName.isNotEmpty
                  ? p.fullName.characters.first.toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: RelativesScreen._accent, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👨‍👩‍👧', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  String _sideLabel(String side) {
    switch (side) {
      case 'paternal':
        return 'Ота томон';
      case 'maternal':
        return 'Она томон';
      default:
        return '';
    }
  }

  String _fmtDay(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}';
  }
}
