import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/circle.dart';
import '../../../repositories/circles_repository.dart';
import '../utils/circle_type_spec.dart';
import 'circle_profile_form_screen.dart';
import 'circle_screen.dart';

/// Universal "Davralarim" ro'yxati — tip bo'yicha filtrlangan (`spec`).
class CirclesListScreen extends StatefulWidget {
  const CirclesListScreen({super.key, required this.spec});

  final CircleTypeSpec spec;

  static const accent = Color(0xFF6A4C93);

  @override
  State<CirclesListScreen> createState() => _CirclesListScreenState();
}

class _CirclesListScreenState extends State<CirclesListScreen> {
  final _repo = CirclesRepository();
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

  Future<void> _openForm() async {
    final phone = _phone;
    if (phone == null || phone.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аввал профилда телефонни тасдиқланг.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CircleProfileFormScreen(spec: widget.spec, phone: phone),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: Text(widget.spec.title),
        backgroundColor: CirclesListScreen.accent,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: CirclesListScreen.accent,
        foregroundColor: Colors.white,
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Давра топиш / яратиш'),
      ),
      body: phone == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<String>>(
              stream: _repo.watchMyCircleIds(phone),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ids = snap.data ?? const <String>[];
                if (ids.isEmpty) return _empty();
                return FutureBuilder<List<Circle>>(
                  future: _loadCircles(ids),
                  builder: (context, cs) {
                    final circles = (cs.data ?? const <Circle>[])
                        .where((c) => c.type == widget.spec.type)
                        .toList();
                    if (cs.connectionState == ConnectionState.waiting &&
                        circles.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (circles.isEmpty) return _empty();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: circles.length,
                      itemBuilder: (_, i) => _circleTile(circles[i], phone),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<List<Circle>> _loadCircles(List<String> ids) async {
    final results = await Future.wait(ids.map(_repo.getCircle));
    return results.whereType<Circle>().toList();
  }

  Widget _circleTile(Circle c, String phone) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0x226A4C93),
          child: Text(widget.spec.emoji, style: const TextStyle(fontSize: 20)),
        ),
        title:
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${c.memberCount} аъзо'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CircleScreen(circleId: c.id, phone: phone),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.spec.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Ҳали даврага қўшилмагансиз.\n«Давра топиш / яратиш» орқали қўшилинг.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
