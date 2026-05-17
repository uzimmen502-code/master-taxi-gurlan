import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';
import '../services/admin_auth_service.dart';

class BirthdayBonusScreen extends StatefulWidget {
  const BirthdayBonusScreen({super.key});

  @override
  State<BirthdayBonusScreen> createState() => _BirthdayBonusScreenState();
}

class _BirthdayBonusScreenState extends State<BirthdayBonusScreen> {
  static const _blue = Color(0xFF0D47A1);
  final _amountCtrl = TextEditingController();
  bool _amountPrimed = false;
  bool _savingAmount = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      _settingsCard(),
      Expanded(
        child: StreamBuilder<List<UserModel>>(
          stream: context.read<UserRepository>().watchUsersWithBirthDate(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Хатолик: ${snap.error}'));
            }
            final now = DateTime.now();
            final users = (snap.data ?? const <UserModel>[])
                .where((u) => _isBirthdayToday(u.birthDate, now))
                .toList();
            if (users.isEmpty) {
              return const _EmptyBirthdayState();
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              itemCount: users.length,
              itemBuilder: (_, i) => _BirthdayUserCard(user: users[i]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.card_giftcard, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Birthday bonus',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                'Бугун туғилган кун бўлган user’ларга йиллик бонус бериш',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _settingsCard() {
    final repo = context.read<UserRepository>();
    return StreamBuilder<int>(
      stream: repo.watchBirthdayBonusAmount(),
      builder: (context, snap) {
        final amount = snap.data ?? 10000;
        if (!_amountPrimed) {
          _amountCtrl.text = amount.toString();
          _amountPrimed = true;
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.savings_outlined, color: _blue),
            const SizedBox(width: 10),
            const Text('Бонус суммаси:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  suffixText: 'сўм',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _savingAmount
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _savingAmount = true);
                      try {
                        await repo.setBirthdayBonusAmount(
                            int.tryParse(_amountCtrl.text.trim()) ?? amount);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Бонус суммаси сақланди'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _savingAmount = false);
                      }
                    },
              icon: _savingAmount
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 16),
              label: const Text('Сақлаш'),
            ),
            const Spacer(),
            Text(
              'Қоида: 1 user = 1 йилда 1 марта',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

class _BirthdayUserCard extends StatefulWidget {
  const _BirthdayUserCard({required this.user});

  final UserModel user;

  @override
  State<_BirthdayUserCard> createState() => _BirthdayUserCardState();
}

class _BirthdayUserCardState extends State<_BirthdayUserCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final repo = context.read<UserRepository>();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFF3E0),
            child: Icon(Icons.cake_outlined, color: Color(0xFFE65100)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.name.isEmpty ? widget.user.id : widget.user.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Телефон: ${widget.user.phone}'),
                Text('Туғилган кун: ${widget.user.birthDate}'),
              ],
            ),
          ),
          StreamBuilder<int>(
            stream: repo.watchBirthdayBonusAmount(),
            builder: (context, amountSnap) {
              final amount = amountSnap.data ?? 10000;
              return FutureBuilder<bool>(
                future: repo.hasBirthdayBonusClaim(uid: widget.user.id, year: year),
                builder: (context, claimSnap) {
                  final claimed = claimSnap.data == true;
                  if (claimed) {
                    return const Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('Бу йил берилган'),
                    );
                  }
                  return ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _grant(context, amount: amount, year: year),
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.card_giftcard, size: 16),
                    label: Text('$amount сўм бериш'),
                  );
                },
              );
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _grant(
    BuildContext context, {
    required int amount,
    required int year,
  }) async {
    setState(() => _busy = true);
    final repo = context.read<UserRepository>();
    final auth = context.read<AdminAuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.grantBirthdayBonus(
        uid: widget.user.id,
        year: year,
        amount: amount,
        operatorPhone: auth.phone ?? '',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Birthday bonus берилди'),
        backgroundColor: Colors.green,
      ));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message == 'birthday_bonus_already_claimed'
            ? 'Бу user бу йил birthday bonus олган'
            : 'Хатолик: ${e.message}'),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _EmptyBirthdayState extends StatelessWidget {
  const _EmptyBirthdayState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_available, size: 54, color: Colors.green.shade400),
        const SizedBox(height: 10),
        const Text('Бугун туғилган куни бўлган user топилмади'),
      ]),
    );
  }
}

bool _isBirthdayToday(String birthDate, DateTime now) {
  final parts = birthDate.split('-');
  if (parts.length != 3) return false;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  return month == now.month && day == now.day;
}
