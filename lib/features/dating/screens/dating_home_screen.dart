import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/dating_interest.dart';
import '../../../models/dating_match.dart';
import '../../../models/dating_profile.dart';
import '../../../repositories/dating_repository.dart';
import '../services/dating_service.dart';
import 'dating_chat_screen.dart';
import 'dating_profile_form_screen.dart';
import 'dating_profile_view_screen.dart';

/// Tab matnlari — AppBar (datingAccent) ustida bir xil oq rang.
abstract final class _DatingTabStyle {
  static const label = Color(0xFFFFFFFF);
}

Tab _datingTab({
  required TabController controller,
  required int index,
  required String label,
}) {
  return Tab(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.index == index;
        return Text(
          label,
          style: TextStyle(
            color: selected
                ? _DatingTabStyle.label
                : _DatingTabStyle.label.withValues(alpha: 0.7),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            fontSize: selected ? 15 : 13,
            letterSpacing: 0.15,
            shadows: selected
                ? const [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        );
      },
    ),
  );
}

/// ❤️ Tanishuv — asosiy ekran. Profil holatiga qarab gate (onboarding /
/// moderatsiya kutilmoqda / faol).
class DatingHomeScreen extends StatefulWidget {
  const DatingHomeScreen({super.key});

  @override
  State<DatingHomeScreen> createState() => _DatingHomeScreenState();
}

class _DatingHomeScreenState extends State<DatingHomeScreen> {
  final _repo = DatingRepository();
  String? _uid;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _uid = uid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (uid.length < 12) {
      return _simpleScaffold(
        'Танишув',
        _info('Аввал профилда телефонни тасдиқланг.'),
      );
    }
    return StreamBuilder<DatingProfile?>(
      stream: _repo.watchMyProfile(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final profile = snap.data;
        if (profile == null) {
          return _onboarding(uid);
        }
        if (profile.status != 'approved') {
          return _statusGate(uid, profile);
        }
        return _DatingApprovedHome(uid: uid, profile: profile, repo: _repo);
      },
    );
  }

  Widget _onboarding(String uid) {
    return _simpleScaffold(
      'Танишув',
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('❤️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text('Турмуш ўртоғингизни топинг',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Профил яратинг — у админ модерациясидан ўтгач, бошқа '
                'фойдаланувчиларга кўринади. Фақат реал расм юкланг.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openForm(uid, null),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: datingAccent,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.add),
                  label: const Text('Профил яратиш'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusGate(String uid, DatingProfile p) {
    final blocked = p.status == 'blocked';
    final rejected = p.status == 'rejected';
    return _simpleScaffold(
      'Танишув',
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(blocked ? '⛔' : (rejected ? '⚠️' : '⏳'),
                  style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              Text(
                blocked
                    ? 'Профилингиз блокланган'
                    : rejected
                        ? 'Профил рад этилди'
                        : 'Профил текширувда',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                blocked
                    ? 'Қоидабузарлик аниқланди. Қўллаб-қувватлашга мурожаат қилинг.'
                    : rejected
                        ? (p.rejectionReason.isNotEmpty
                            ? 'Сабаб: ${p.rejectionReason}\nТаҳрирлаб қайта юборинг.'
                            : 'Профилни таҳрирлаб қайта юборинг.')
                        : 'Админ тасдиғини кутинг. Одатда қисқа вақт ичида.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 22),
              if (!blocked)
                OutlinedButton.icon(
                  onPressed: () => _openForm(uid, p),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Профилни таҳрирлаш'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(String uid, DatingProfile? existing) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DatingProfileFormScreen(uid: uid, existing: existing),
      ),
    );
  }

  Widget _simpleScaffold(String title, Widget body) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F6),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: datingAccent,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _info(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
}

/// Tasdiqlangan profil egasi uchun 4 tab.
class _DatingApprovedHome extends StatelessWidget {
  const _DatingApprovedHome({
    required this.uid,
    required this.profile,
    required this.repo,
  });

  final String uid;
  final DatingProfile profile;
  final DatingRepository repo;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) {
          final tabCtrl = DefaultTabController.of(context);
          return Scaffold(
            backgroundColor: const Color(0xFFF7F4F6),
            appBar: AppBar(
              title: const Text('Танишув'),
              backgroundColor: datingAccent,
              foregroundColor: Colors.white,
              bottom: TabBar(
                controller: tabCtrl,
                isScrollable: true,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                dividerColor: Colors.transparent,
                tabs: [
                  _datingTab(
                    controller: tabCtrl,
                    index: 0,
                    label: '🔍 Тавсия',
                  ),
                  _datingTab(
                    controller: tabCtrl,
                    index: 1,
                    label: '❤️ Қизиқишлар',
                  ),
                  _datingTab(
                    controller: tabCtrl,
                    index: 2,
                    label: '💬 Чатлар',
                  ),
                  _datingTab(
                    controller: tabCtrl,
                    index: 3,
                    label: '👤 Профил',
                  ),
                ],
              ),
            ),
            body: TabBarView(
              controller: tabCtrl,
              children: [
                _DiscoveryTab(uid: uid, profile: profile, repo: repo),
                _InterestsTab(uid: uid, repo: repo),
                _MatchesTab(uid: uid, repo: repo),
                _MyProfileTab(uid: uid, profile: profile),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Tavsiya ──────────────────────────────────────────────────────────
class _DiscoveryTab extends StatelessWidget {
  const _DiscoveryTab(
      {required this.uid, required this.profile, required this.repo});
  final String uid;
  final DatingProfile profile;
  final DatingRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: repo.watchBlockedIds(uid),
      builder: (context, blockSnap) {
        final blocked = blockSnap.data ?? const <String>{};
        return StreamBuilder<List<DatingProfile>>(
          stream: repo.watchDiscovery(
            myUid: uid,
            myGender: profile.gender,
            excludeIds: blocked,
            prefMinAge: profile.prefMinAge,
            prefMaxAge: profile.prefMaxAge,
          ),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const <DatingProfile>[];
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Танланган ёш оралиғида (${profile.prefMinAge}–'
                    '${profile.prefMaxAge}) ҳозирча мос профил йўқ.\n'
                    'Профил табида оралиқни кенайтиринг.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _DiscoveryCard(
                profile: list[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DatingProfileViewScreen(
                        myUid: uid, profile: list[i]),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.profile, required this.onTap});
  final DatingProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (profile.firstPhoto.isNotEmpty)
              Image.network(profile.firstPhoto, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: datingAccent.withValues(alpha: 0.1)))
            else
              Container(color: datingAccent.withValues(alpha: 0.1)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.age != null
                          ? '${profile.displayName}, ${profile.age}'
                          : profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    if (profile.city.isNotEmpty)
                      Text('📍 ${profile.city}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Qiziqishlar ──────────────────────────────────────────────────────
class _InterestsTab extends StatelessWidget {
  const _InterestsTab({required this.uid, required this.repo});
  final String uid;
  final DatingRepository repo;

  Future<void> _respond(
      BuildContext context, DatingInterest it, bool accept) async {
    try {
      final res = await DatingService.respondInterest(it.id, accept);
      if (!context.mounted) return;
      if (res['status'] == 'accepted') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 Мослашув! «Чатлар»да ёзишинг мумкин.')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(firebaseFunctionsUserMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatingInterest>>(
      stream: repo.watchIncomingInterests(uid),
      builder: (context, snap) {
        final incoming = snap.data ?? const <DatingInterest>[];
        if (incoming.isEmpty) {
          return Center(
            child: Text('Сизга юборилган қизиқиш йўқ.',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: incoming.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final it = incoming[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: datingAccent.withValues(alpha: 0.15),
                child: Text(
                  it.fromName.isNotEmpty
                      ? it.fromName.characters.first.toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: datingAccent, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(it.fromName.isEmpty ? 'Фойдаланувчи' : it.fromName),
              subtitle: const Text('Сизга қизиқиш билдирди'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () => _respond(context, it, true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                    onPressed: () => _respond(context, it, false),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Chatlar (match) ──────────────────────────────────────────────────
class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.uid, required this.repo});
  final String uid;
  final DatingRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatingMatch>>(
      stream: repo.watchMatches(uid),
      builder: (context, snap) {
        final matches = snap.data ?? const <DatingMatch>[];
        if (matches.isEmpty) {
          return Center(
            child: Text('Ҳали мослашув йўқ.',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: matches.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final m = matches[i];
            final name = m.otherName(uid);
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: datingAccent.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                  style: const TextStyle(
                      color: datingAccent, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(name.isEmpty ? 'Чат' : name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                m.lastMessage.isEmpty ? 'Ёзишувни бошланг' : m.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DatingChatScreen(myUid: uid, match: m),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Mening profilim ──────────────────────────────────────────────────
class _MyProfileTab extends StatefulWidget {
  const _MyProfileTab({required this.uid, required this.profile});
  final String uid;
  final DatingProfile profile;

  @override
  State<_MyProfileTab> createState() => _MyProfileTabState();
}

class _MyProfileTabState extends State<_MyProfileTab> {
  bool _busy = false;
  bool _savingAge = false;
  late RangeValues _ageRange;

  @override
  void initState() {
    super.initState();
    _ageRange = _rangeFromProfile(widget.profile);
  }

  @override
  void didUpdateWidget(covariant _MyProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.prefMinAge != widget.profile.prefMinAge ||
        oldWidget.profile.prefMaxAge != widget.profile.prefMaxAge) {
      _ageRange = _rangeFromProfile(widget.profile);
    }
  }

  RangeValues _rangeFromProfile(DatingProfile p) {
    final lo = p.prefMinAge.clamp(18, 80).toDouble();
    final hi = p.prefMaxAge.clamp(18, 80).toDouble();
    return RangeValues(math.min(lo, hi), math.max(lo, hi));
  }

  Future<void> _saveAgePreference() async {
    final minAge = _ageRange.start.round();
    final maxAge = _ageRange.end.round();
    if (minAge == widget.profile.prefMinAge &&
        maxAge == widget.profile.prefMaxAge) {
      return;
    }
    setState(() => _savingAge = true);
    try {
      await DatingService.setAgePreference(minAge: minAge, maxAge: maxAge);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ёш оралиғи сақланди')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firebaseFunctionsUserMessage(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хатолик: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAge = false);
    }
  }

  Future<void> _toggleActive(bool v) async {
    setState(() => _busy = true);
    try {
      await DatingService.setActive(v);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProfile() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Профилни ўчириш'),
        content: const Text(
          'Танишув профили, расмлар, қизиқишлар ва чатлар '
          'бутунлай ўчирилади. Бу амални қайтариб бўлмайди.\n\n'
          'Давом этасизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ўчираман'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await DatingService.deleteProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профил ўчирилди')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firebaseFunctionsUserMessage(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хатолик: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CircleAvatar(
            radius: 54,
            backgroundColor: datingAccent.withValues(alpha: 0.15),
            backgroundImage:
                p.firstPhoto.isNotEmpty ? NetworkImage(p.firstPhoto) : null,
            child: p.firstPhoto.isEmpty
                ? const Icon(Icons.person, size: 48, color: datingAccent)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            p.age != null ? '${p.displayName}, ${p.age}' : p.displayName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Center(
          child: Text('✓ ${p.statusLabel}',
              style: const TextStyle(color: Colors.green)),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          activeThumbColor: datingAccent,
          title: const Text('Профил кўринади'),
          subtitle: const Text('Ўчирсангиз тавсиада чиқмайсиз'),
          value: p.active,
          onChanged: _busy ? null : _toggleActive,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Тавсия ёш оралиғи: ${_ageRange.start.round()} – '
            '${_ageRange.end.round()} ёш',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        RangeSlider(
          values: _ageRange,
          min: 18,
          max: 80,
          divisions: 62,
          activeColor: datingAccent,
          labels: RangeLabels(
            '${_ageRange.start.round()}',
            '${_ageRange.end.round()}',
          ),
          onChanged: _savingAge
              ? null
              : (v) => setState(() => _ageRange = v),
          onChangeEnd: (_) => _saveAgePreference(),
        ),
        if (_savingAge)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Профилни таҳрирлаш'),
          subtitle: const Text('Ўзгартиргач қайта модерациядан ўтади'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DatingProfileFormScreen(uid: widget.uid, existing: p),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: const Text(
            'Профилни ўчириш',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Расмлар, қизиқишлар ва чатлар ҳам ўчирилади',
          ),
          enabled: !_busy,
          onTap: _busy ? null : _deleteProfile,
        ),
      ],
    );
  }
}
