import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/balance_service.dart';
import '../services/admin_auth_service.dart';
import '../../../core/theme/app_theme.dart';

class BirthdayBonusScreen extends StatefulWidget {
  const BirthdayBonusScreen({super.key});

  @override
  State<BirthdayBonusScreen> createState() => _BirthdayBonusScreenState();
}

class _BirthdayBonusScreenState extends State<BirthdayBonusScreen> {
  static const _blue = AppColors.primary;
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
            final users = snap.data ?? const <UserModel>[];
            final columns = _birthdayColumns(DateTime.now(), users);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final column in columns) ...[
                    _BirthdayColumnView(column: column),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
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
                            backgroundColor: AppColors.button,
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

class _BirthdayColumnView extends StatelessWidget {
  const _BirthdayColumnView({required this.column});

  final _BirthdayColumn column;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: column.canGrant
                        ? const Color(0xFFFFF3E0)
                        : Colors.blue.shade50,
                    child: Icon(
                      column.canGrant
                          ? Icons.cake_outlined
                          : Icons.event_available_outlined,
                      color: column.canGrant
                          ? AppColors.primary
                          : Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          column.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          column.dateLabel,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text('${column.users.length}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (column.users.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'User йўқ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              else
                for (final user in column.users)
                  _BirthdayUserCard(
                    user: user,
                    canGrant: column.canGrant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BirthdayUserCard extends StatefulWidget {
  const _BirthdayUserCard({
    required this.user,
    required this.canGrant,
  });

  final UserModel user;
  final bool canGrant;

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
            child: Icon(Icons.cake_outlined, color: AppColors.primary),
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
              if (!widget.canGrant) {
                return const Chip(
                  avatar: Icon(Icons.schedule, size: 16),
                  label: Text('Кутилаяпти'),
                );
              }
              return FutureBuilder<bool>(
                future:
                    repo.hasBirthdayBonusClaim(uid: widget.user.id, year: year),
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
    final auth = context.read<AdminAuthService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BalanceService.grantBirthdayBonus(
        uid: widget.user.id,
        year: year,
        amount: amount,
        operatorPhone: auth.phone ?? '',
      );
      messenger.showSnackBar(const SnackBar(
        content: Text('Birthday bonus берилди'),
        backgroundColor: AppColors.button,
      ));
    } on FirebaseFunctionsException catch (e) {
      final already = e.code == 'already-exists' ||
          (e.message ?? '').contains('birthday_bonus_already_claimed');
      messenger.showSnackBar(SnackBar(
        content: Text(already
            ? 'Бу user бу йил birthday bonus олган'
            : 'Хатолик: ${e.message ?? e.code}'),
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

bool _isBirthdayOnDate(String birthDate, DateTime date) {
  // Ikkala formatni ham qo'llaydi: `YYYY-MM-DD` va `DD.MM.YYYY`.
  final born = parseBirthDate(birthDate);
  if (born == null) return false;
  return born.month == date.month && born.day == date.day;
}

List<_BirthdayColumn> _birthdayColumns(DateTime now, List<UserModel> users) {
  const specs = [
    (0, 'Бугун'),
    (1, 'Эртага'),
    (2, 'Индинга'),
    (3, '3 кундан кейин'),
    (5, '5 кундан кейин'),
    (7, '7 кундан кейин'),
  ];
  return [
    for (final spec in specs)
      _BirthdayColumn(
        title: spec.$2,
        date: now.add(Duration(days: spec.$1)),
        canGrant: spec.$1 == 0,
        users: users
            .where((u) => _isBirthdayOnDate(
                  u.birthDate,
                  now.add(Duration(days: spec.$1)),
                ))
            .toList()
          ..sort((a, b) => (a.name.isEmpty ? a.id : a.name)
              .compareTo(b.name.isEmpty ? b.id : b.name)),
      ),
  ];
}

class _BirthdayColumn {
  const _BirthdayColumn({
    required this.title,
    required this.date,
    required this.canGrant,
    required this.users,
  });

  final String title;
  final DateTime date;
  final bool canGrant;
  final List<UserModel> users;

  String get dateLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}';
  }
}
