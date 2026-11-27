import 'package:flutter/material.dart';

import '../../business_map/domain/business.dart';
import '../../factories/data/factories_repository.dart';

/// «Ишлаб чиқарувчилар» (эга 2026-11-28): «Тасдиқланган ишлаб чиқарувчи» нишони — АВТО/ҚЎЛДА режими
/// (`settings/app.producerVerifyAutoApprove`, `adminSetProducerAutoApprove`), кутаётганлар рўйхати (тасдиқлаш /
/// рад этиш сабаб билан — `adminSetProducerVerification`; ҳаммаси `admin_audit`да) ва «AVA'га таъминотчи бўлишга
/// тайёрман» белгисини қўйган заводлар (фақат кўриш — буюртма мантиғи йўқ).
class ProducerVerificationAdminScreen extends StatefulWidget {
  const ProducerVerificationAdminScreen({super.key, this.repository});

  @visibleForTesting
  final FactoriesRepository? repository;

  @override
  State<ProducerVerificationAdminScreen> createState() => _ProducerVerificationAdminScreenState();
}

class _ProducerVerificationAdminScreenState extends State<ProducerVerificationAdminScreen> {
  late final FactoriesRepository _repo = widget.repository ?? FactoriesRepository();
  late Future<(List<Business>, List<Business>)> _future = _load();
  bool _busy = false;

  Future<(List<Business>, List<Business>)> _load() async {
    final r = await Future.wait([_repo.fetchPendingVerification(), _repo.fetchAvaSuppliers()]);
    return (r[0], r[1]);
  }

  void _reload() => setState(() => _future = _load());

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _decide(Business b, bool approve) async {
    var reason = '';
    if (!approve) {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Рад этиш: ${b.name}'),
          content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Сабаб (камида 3 белги)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Рад этиш')),
          ],
        ),
      );
      reason = ctl.text.trim();
      ctl.dispose();
      if (ok != true) return;
      if (reason.length < 3) {
        _snack('Сабабни ёзинг.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await _repo.adminSetVerification(b.id, approve: approve, reason: reason);
      _snack(approve ? 'Тасдиқланди: ${b.name}' : 'Рад этилди: ${b.name}');
      _reload();
    } catch (e) {
      debugPrint('[ProducerAdmin] PRODUCER_VERIFY_FAILED: $e');
      _snack('Сақлаб бўлмади. Қайта уриниб кўринг.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAuto(bool v) async {
    setState(() => _busy = true);
    try {
      await _repo.adminSetAutoApprove(v);
    } catch (e) {
      debugPrint('[ProducerAdmin] PRODUCER_AUTO_FAILED: $e');
      _snack('Сақлаб бўлмади. Қайта уриниб кўринг.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<bool>(
          stream: _repo.watchAutoApprove(),
          builder: (ctx, snap) {
            final auto = snap.data == true;
            return Card(
              child: SwitchListTile(
                key: const ValueKey('producer_auto_switch'),
                value: auto,
                onChanged: _busy || !snap.hasData ? null : _setAuto,
                title: Text(auto ? 'Тасдиқлаш: АВТО' : 'Тасдиқлаш: ҚЎЛДА'),
                subtitle: const Text('АВТО — завод сўраганда нишон дарҳол берилади; ҚЎЛДА — шу ерда тасдиқланади.'),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        FutureBuilder<(List<Business>, List<Business>)>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.hasError) {
              return Column(children: [
                const Text('Рўйхатни юклаб бўлмади.'),
                TextButton(onPressed: _reload, child: const Text('Қайта уриниш')),
              ]);
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (pending, suppliers) = snap.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Тасдиқ кутаётганлар (${pending.length})', style: Theme.of(ctx).textTheme.titleMedium),
              if (pending.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Йўқ')),
              for (final b in pending)
                Card(
                  key: ValueKey('producer_pending_${b.id}'),
                  child: ListTile(
                    title: Text(b.name),
                    subtitle: Text([b.subtype, b.address, b.ownerId].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        key: ValueKey('producer_approve_${b.id}'),
                        tooltip: 'Тасдиқлаш',
                        icon: const Icon(Icons.verified_rounded, color: Colors.green),
                        onPressed: _busy ? null : () => _decide(b, true),
                      ),
                      IconButton(
                        key: ValueKey('producer_reject_${b.id}'),
                        tooltip: 'Рад этиш',
                        icon: const Icon(Icons.block_rounded, color: Colors.red),
                        onPressed: _busy ? null : () => _decide(b, false),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 20),
              Text("AVA'га таъминотчи бўлишга тайёр (${suppliers.length})", style: Theme.of(ctx).textTheme.titleMedium),
              if (suppliers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Йўқ')),
              for (final b in suppliers)
                Card(
                  key: ValueKey('producer_supplier_${b.id}'),
                  child: ListTile(
                    title: Text(b.name),
                    subtitle: Text([b.subtype, b.address, b.ownerId].where((s) => s.isNotEmpty).join(' · ')),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
