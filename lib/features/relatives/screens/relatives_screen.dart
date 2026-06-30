import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/relative_event.dart';
import '../../../models/relative_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../services/relative_photo_storage.dart';
import '../services/relative_reminder_scheduler.dart';
import '../services/tree_service.dart';
import 'family_tree_screen.dart';
import 'relative_album_screen.dart';
import 'tree_history_screen.dart';
import 'relative_event_form_screen.dart';
import 'relative_form_screen.dart';

/// 👨‍👩‍👧 Qarindoshlarim — shaxsiy ro'yxat + tug'ilgan kunlar.
class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

  static const _accent = Color(0xFF6A4C93);

  @override
  State<RelativesScreen> createState() => _RelativesScreenState();
}

class _RelativesScreenState extends State<RelativesScreen>
    with SingleTickerProviderStateMixin {
  final _repo = RelativesRepository();
  final _photo = RelativePhotoStorage();
  final _scheduler = RelativeReminderScheduler();
  String? _phone;
  List<RelativePerson> _people = const [];
  String? _reminderSig;

  late final TabController _tab;

  /// Tartib: 0 = Ro'yxat, 1 = Nasab daraxti, 2 = Sanalar.
  static const int _treeTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      ..addListener(() {
        // FAB faqat kerakli tabda ko'rinishi uchun qayta chizamiz.
        if (mounted) setState(() {});
      });
    _loadPhone();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _phone = phone);
    // Faza 1: global nasab grafiga komponent + migratsiya (idempotent,
    // fonda — UI'ga ta'sir qilmaydi).
    if (phone.length >= 12) {
      unawaited(TreeService.ensureMyTree().catchError(
          (_) => <String, dynamic>{}));
    }
  }

  Future<void> _add() async {
    final phone = _phone;
    if (phone == null || phone.length < 12) {
      _snack('Аввал профилда телефонни тасдиқланг.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelativeFormScreen(userId: phone, allPeople: _people),
      ),
    );
  }

  Future<void> _edit(RelativePerson p) async {
    final phone = _phone!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RelativeFormScreen(userId: phone, existing: p, allPeople: _people),
      ),
    );
  }

  /// Nasab daraxtidan o'z qarindoshini id bo'yicha tahrirlash.
  void _editById(String nodeId) {
    final match = _people.where((p) => p.id == nodeId);
    if (match.isEmpty) return;
    _edit(match.first);
  }

  void _openHistory(String phone) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TreeHistoryScreen(userId: phone)),
    );
  }

  Future<void> _addEvent() async {
    final phone = _phone;
    if (phone == null || phone.length < 12) {
      _snack('Аввал профилда телефонни тасдиқланг.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RelativeEventFormScreen(userId: phone, allPeople: _people),
      ),
    );
  }

  Future<void> _editEvent(RelativeEvent e) async {
    final phone = _phone!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelativeEventFormScreen(
            userId: phone, existing: e, allPeople: _people),
      ),
    );
  }

  Future<void> _openAlbum(RelativePerson p) async {
    final phone = _phone!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelativeAlbumScreen(userId: phone, person: p),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text('Қариндошларим'),
        backgroundColor: RelativesScreen._accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Дарахт тарихи',
            icon: const Icon(Icons.history),
            onPressed: phone == null ? null : () => _openHistory(phone),
          ),
          IconButton(
            tooltip: 'Сана / учрашув қўшиш',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: _addEvent,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Рўйхат'),
            Tab(text: '🌳 Насаб дарахти'),
            Tab(text: '📅 Саналар'),
          ],
        ),
      ),
      // FAB ("Қариндош") nasab daraxti tabida ko'rinmaydi — daraxt ro'yxatdan
      // quriladi, bu yerda qo'shish chalkashtiradi.
      floatingActionButton: _tab.index == _treeTabIndex
          ? null
          : FloatingActionButton.extended(
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
                _people = people;
                return TabBarView(
                  controller: _tab,
                  children: [
                    _listTab(people),
                    FamilyTreeScreen(
                      userId: phone,
                      onEditOwnNode: _editById,
                    ),
                    _datesTab(people),
                  ],
                );
              },
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
              if (v == 'album') _openAlbum(p);
              if (v == 'edit') _edit(p);
              if (v == 'delete') _delete(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'album', child: Text('📷 Альбом')),
              PopupMenuItem(value: 'edit', child: Text('Таҳрирлаш')),
              PopupMenuItem(value: 'delete', child: Text('Ўчириш')),
            ],
          ),
        ],
      ),
    );
  }

  /// 📅 Туғилган кунлар (авто) + махсус саналар — бирлашган, кун бўйича тартибли.
  Widget _datesTab(List<RelativePerson> people) {
    final phone = _phone;
    if (phone == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<RelativeEvent>>(
      stream: _repo.watchEvents(phone),
      builder: (context, snap) {
        final events = _repo.upcomingEvents(snap.data ?? const []);
        _syncReminders(people, events);
        final items = _buildReminders(people, events)
          ..sort((a, b) => a.days.compareTo(b.days));
        if (items.isEmpty) {
          return _empty('Ҳали сана йўқ.\n⊕ тугмаси орқали учрашув ёки '
              'муҳим сана қўшинг.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _reminderTile(items[i]),
        );
      },
    );
  }

  /// OS eslatmalarini (qayta) rejalashtirish — faqat ma'lumot o'zgarganda.
  void _syncReminders(
      List<RelativePerson> people, List<RelativeEvent> events) {
    final sig = [
      ...people
          .where((p) => p.birthDate != null)
          .map((p) => 'b${p.id}:${p.daysUntilBirthday}'),
      ...events.map((e) => 'e${e.id}:${e.daysUntil}'),
    ].join('|');
    if (sig == _reminderSig) return;
    _reminderSig = sig;
    unawaited(_scheduler.sync(people: people, events: events));
  }

  List<_Reminder> _buildReminders(
      List<RelativePerson> people, List<RelativeEvent> events) {
    final byId = {for (final p in people) p.id: p};
    final out = <_Reminder>[];

    for (final p in people) {
      final days = p.daysUntilBirthday;
      if (days == null) continue;
      final nb = p.nextBirthday;
      final turning = (p.age ?? 0) + (days == 0 ? 0 : 1);
      out.add(_Reminder(
        days: days,
        leading: _avatar(p),
        title: '🎂 ${p.fullName}',
        subtitle: nb == null ? '' : '${_fmtDay(nb)} · $turning ёшга тўлади',
        onTap: () => _edit(p),
      ));
    }

    for (final e in events) {
      final names = e.personIds
          .map((id) => byId[id]?.fullName)
          .whereType<String>()
          .join(', ');
      final sub = [
        _fmtDay(e.nextOccurrence),
        if (e.repeatYearly) 'ҳар йили',
        if (e.place.isNotEmpty) e.place,
        if (names.isNotEmpty) names,
      ].join(' · ');
      out.add(_Reminder(
        days: e.daysUntil,
        leading: CircleAvatar(
          backgroundColor: RelativesScreen._accent.withValues(alpha: 0.15),
          child: Text(e.type.emoji, style: const TextStyle(fontSize: 18)),
        ),
        title: e.title,
        subtitle: sub,
        onTap: () => _editEvent(e),
      ));
    }
    return out;
  }

  Widget _reminderTile(_Reminder r) {
    return ListTile(
      leading: r.leading,
      title:
          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle),
      trailing: _daysBadge(r.days),
      onTap: r.onTap,
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

/// "Саналар" табидаги бирлашган элемент (туғилган кун ёки махсус сана).
class _Reminder {
  _Reminder({
    required this.days,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final int days;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
