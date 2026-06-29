import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../models/dating_profile.dart';
import '../../../repositories/dating_repository.dart';
import '../services/dating_service.dart';
import 'dating_profile_form_screen.dart';

/// Boshqa foydalanuvchi profilini ko'rish + qiziqish bildirish / shikoyat / blok.
class DatingProfileViewScreen extends StatefulWidget {
  const DatingProfileViewScreen({
    super.key,
    required this.myUid,
    required this.profile,
  });

  final String myUid;
  final DatingProfile profile;

  @override
  State<DatingProfileViewScreen> createState() =>
      _DatingProfileViewScreenState();
}

class _DatingProfileViewScreenState extends State<DatingProfileViewScreen> {
  final _repo = DatingRepository();
  final _pageCtrl = PageController();
  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendInterest() async {
    setState(() => _busy = true);
    try {
      final res = await DatingService.sendInterest(widget.profile.userId);
      if (!mounted) return;
      if (res['matched'] == true) {
        _snack('🎉 Мослашув! Энди ёзишувингиз мумкин.');
      } else if (res['alreadySent'] == true) {
        _snack('Қизиқиш аввал юборилган.');
      } else {
        _snack('Қизиқиш юборилди.');
      }
      Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      _snack(firebaseFunctionsUserMessage(e));
    } catch (e) {
      _snack('Хатолик: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _block() async {
    final ok = await _confirm('Блоклаш',
        '«${widget.profile.displayName}» ни блокласизми? У сизни кўрмайди.');
    if (ok != true) return;
    await _repo.block(widget.myUid, widget.profile.userId);
    if (mounted) {
      _snack('Блокланди.');
      Navigator.pop(context);
    }
  }

  Future<void> _report() async {
    final ctrl = TextEditingController();
    final String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Шикоят'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Сабабини ёзинг (масалан: сохта профил)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Бекор')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Юбориш'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (reason == null || reason.isEmpty) return;
    await _repo.report(
      reporterId: widget.myUid,
      targetId: widget.profile.userId,
      reason: reason,
    );
    if (mounted) _snack('Шикоят юборилди. Раҳмат.');
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final isSelf = p.userId == widget.myUid;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F6),
      appBar: AppBar(
        title: Text(p.displayName),
        backgroundColor: datingAccent,
        foregroundColor: Colors.white,
        actions: [
          if (!isSelf)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'report') _report();
                if (v == 'block') _block();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('🚩 Шикоят')),
                PopupMenuItem(value: 'block', child: Text('⛔ Блоклаш')),
              ],
            ),
        ],
      ),
      body: ListView(
        children: [
          _photoCarousel(p),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.age != null
                            ? '${p.displayName}, ${p.age}'
                            : p.displayName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _chips(p),
                if (p.about.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Ўзи ҳақида',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(p.about, style: const TextStyle(height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isSelf
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _sendInterest,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: datingAccent,
                        foregroundColor: Colors.white),
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.favorite),
                    label: const Text('Қизиқиш билдириш'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _photoCarousel(DatingProfile p) {
    if (p.photos.isEmpty) {
      return Container(
        height: 360,
        color: datingAccent.withValues(alpha: 0.1),
        child: const Icon(Icons.person, size: 96, color: datingAccent),
      );
    }
    return SizedBox(
      height: 360,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: p.photos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Image.network(
              p.photos[i].url,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined, size: 64),
            ),
          ),
          if (p.photos.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < p.photos.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chips(DatingProfile p) {
    final items = <String>[
      if (p.city.isNotEmpty) '📍 ${p.city}',
      if (p.maritalStatus.isNotEmpty) _maritalLabel(p.maritalStatus),
      if (p.education.isNotEmpty) '🎓 ${p.education}',
      if (p.job.isNotEmpty) '💼 ${p.job}',
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .map((t) => Chip(
                label: Text(t),
                backgroundColor: datingAccent.withValues(alpha: 0.08),
                side: BorderSide(color: datingAccent.withValues(alpha: 0.2)),
              ))
          .toList(),
    );
  }

  String _maritalLabel(String m) {
    switch (m) {
      case 'single':
        return 'Бўйдоқ';
      case 'divorced':
        return 'Ажрашган';
      case 'widowed':
        return 'Бева';
      default:
        return '';
    }
  }
}
