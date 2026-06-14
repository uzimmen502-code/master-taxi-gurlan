import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/sell_offer_item.dart';
import '../../../models/sell_submission.dart';
import '../../../models/user_address.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../repositories/sell_offers_repository.dart';
import '../../../repositories/user_repository.dart';

/// Бирлашган сотиш формаси — платформа ва/ёки «Сотаман» (P2P).
class SellOfferForm extends StatefulWidget {
  const SellOfferForm({
    super.key,
    required this.phone,
    required this.phoneOk,
    this.defaultToPlatform = true,
    this.defaultToPublic = false,
  });

  final String phone;
  final bool phoneOk;

  /// Профил «Сотиш» — платформа асосий.
  final bool defaultToPlatform;

  /// Иш топ «Сотаман» — омма эълони асосий.
  final bool defaultToPublic;

  @override
  State<SellOfferForm> createState() => _SellOfferFormState();
}

class _SellOfferFormState extends State<SellOfferForm> {
  static const _green = AppColors.primaryDark;
  static const _brown = AppColors.primarySoft;

  final List<_DraftRow> _rows = [_DraftRow()];
  bool _submitting = false;
  late bool _toPlatform;
  late bool _toPublic;

  @override
  void initState() {
    super.initState();
    _toPlatform = widget.defaultToPlatform;
    _toPublic = widget.defaultToPublic;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_DraftRow()));
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!widget.phoneOk) {
      _snack('Аввал профилда телефонни киритинг', error: true);
      return;
    }
    if (!_toPlatform && !_toPublic) {
      _snack('Камida битта йўналишни белгиланг', error: true);
      return;
    }

    final items = <SellOfferItem>[];
    for (var i = 0; i < _rows.length; i++) {
      final item = _rows[i].toItem();
      if (item == null) {
        _snack('${i + 1}-маҳсулот: барча майдонларни тўлдиринг', error: true);
        return;
      }
      items.add(item);
    }

    setState(() => _submitting = true);
    final sellRepo = context.read<SellOffersRepository>();
    final jobsRepo = context.read<JobsRepository>();
    final userRepo = context.read<UserRepository>();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final uid = phoneDigits(widget.phone);
      final name = prefs.getString('user_name') ?? '';
      final legacyAddress = prefs.getString('user_address') ?? '';

      UserAddress structured = const UserAddress();
      try {
        final user = await userRepo.getById(uid);
        if (user != null) {
          structured = user.address;
          if (legacyAddress.isEmpty && user.addressLegacy.isNotEmpty) {
            // legacy fallback below
          }
        }
      } catch (_) {}

      final pickupFields = SellSubmission.pickupFieldsFromAddress(
        address: structured,
        legacy: legacyAddress,
      );
      final pickupText = (pickupFields['pickupAddress'] as String?) ?? '';

      if (_toPlatform && pickupText.isEmpty) {
        _snack(
          'Платформа таклифи учун профилда тўliq манzil (GPS) киритинг',
          error: true,
        );
        setState(() => _submitting = false);
        return;
      }

      var publishedPlatform = false;
      var publishedPublic = false;

      if (_toPlatform) {
        final draft = SellSubmission(
          id: '',
          userId: uid,
          userPhone: uid,
          userName: name,
          items: items,
          status: 'pending',
          createdAt: DateTime.now(),
          pickupAddress: pickupText,
          pickupLat: (pickupFields['pickupLat'] as num?)?.toDouble(),
          pickupLng: (pickupFields['pickupLng'] as num?)?.toDouble(),
          pickupNote: structured.note,
        );
        await sellRepo.createWithPickup(draft, pickupFields);
        publishedPlatform = true;
      }

      if (_toPublic) {
        final daily = await jobsRepo.dailyCountByAuthor(uid);
        if (daily >= SellOffersRepository.dailyPublicAdLimit) {
          if (!publishedPlatform) {
            _snack(
              'Кунига максимум ${SellOffersRepository.dailyPublicAdLimit} та «Сотаман» эълони!',
              error: true,
            );
            return;
          }
        } else {
          await sellRepo.publishAsPublicAd(
            jobsRepo: jobsRepo,
            items: items,
            authorName: name,
            authorPhone: uid,
            address: pickupText.isNotEmpty ? pickupText : legacyAddress,
          );
          publishedPublic = true;
        }
      }

      if (!mounted) return;
      final parts = <String>[];
      if (publishedPlatform) parts.add('платформа');
      if (publishedPublic) parts.add('«Сотаман» (текширувда)');
      if (_toPublic && !publishedPublic && publishedPlatform) {
        parts.add('«Сотаман» лимити тўлди');
      }
      _snack(
        parts.isEmpty
            ? 'Юборилмади'
            : 'Таклиф юборилди: ${parts.join(' · ')}',
      );

      setState(() {
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..add(_DraftRow());
        _submitting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('Хатолик: $e', error: true);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red.shade700 : _green,
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = phoneDigits(widget.phone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              CheckboxListTile(
                value: _toPlatform,
                onChanged: widget.phoneOk && !_submitting
                    ? (v) => setState(() => _toPlatform = v ?? false)
                    : null,
                title: const Text(
                  'Платформага таклиф',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Master Taxi харид қилиши мумкин — оператор боғланади',
                  style: TextStyle(fontSize: 12),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: _green,
              ),
              const Divider(height: 1),
              CheckboxListTile(
                value: _toPublic,
                onChanged: widget.phoneOk && !_submitting
                    ? (v) => setState(() => _toPublic = v ?? false)
                    : null,
                title: const Text(
                  'Барча фойдаланувчига (Сотаман)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Иш топ — «Сотаман» бўлимида эълон (модерациядан кейин)',
                  style: TextStyle(fontSize: 12),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: _brown,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Маҳсулотлар',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.phoneOk
              ? 'Номи, миқдори, такlif нархи. «+» билан яна қўшинг.'
              : 'Телефон киритилгандан кейин юбориш мумкин.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
        ),
        const SizedBox(height: 12),
        ...List.generate(_rows.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OfferCard(
              index: i,
              row: _rows[i],
              canRemove: _rows.length > 1,
              enabled: widget.phoneOk && !_submitting,
              onRemove: () => _removeRow(i),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: widget.phoneOk && !_submitting ? _addRow : null,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Яна маҳсулот (+)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _brown,
            side: BorderSide(color: _brown.withValues(alpha: 0.5)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.phoneOk && !_submitting ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_submitting ? 'Юборилмоқда…' : 'Таклифни юбориш'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (widget.phoneOk) ...[
          const SizedBox(height: 20),
          const Text(
            'Платформага юборилганлар',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<SellSubmission>>(
            stream: context.read<SellOffersRepository>().watchByUser(uid),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return Text(
                  'Ҳали платформа таклифи йўқ',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                );
              }
              return Column(
                children: list
                    .map((s) => _HistoryTile(submission: s))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _DraftRow {
  _DraftRow()
      : nameCtrl = TextEditingController(),
        qtyCtrl = TextEditingController(),
        priceCtrl = TextEditingController();

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  bool isRecurring = false;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }

  SellOfferItem? toItem() {
    final name = nameCtrl.text.trim();
    final qty = qtyCtrl.text.trim();
    final price = int.tryParse(priceCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (name.isEmpty || qty.isEmpty || price <= 0) return null;
    return SellOfferItem(
      productName: name,
      quantityText: qty,
      priceOffered: price,
      isRecurring: isRecurring,
    );
  }
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({
    required this.index,
    required this.row,
    required this.canRemove,
    required this.enabled,
    required this.onRemove,
  });

  final int index;
  final _DraftRow row;
  final bool canRemove;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  static const _brown = AppColors.primarySoft;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _brown.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Маҳсулот ${widget.index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  onPressed: widget.enabled ? widget.onRemove : null,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Ўчириш',
                  color: Colors.red.shade400,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.nameCtrl,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Маҳсулот номи',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.qtyCtrl,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Миқдор (матн)',
              hintText: 'масалан: 5 кг, 20 дона',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.priceCtrl,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Такlif нархи (сўм)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Бир марта'),
                icon: Icon(Icons.looks_one_outlined, size: 18),
              ),
              ButtonSegment(
                value: true,
                label: Text('Доимий'),
                icon: Icon(Icons.repeat, size: 18),
              ),
            ],
            selected: {row.isRecurring},
            onSelectionChanged: widget.enabled
                ? (s) => setState(() => row.isRecurring = s.first)
                : null,
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.submission});

  final SellSubmission submission;

  @override
  Widget build(BuildContext context) {
    final date = submission.createdAt;
    final when =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final summary = submission.items
        .map((e) => '${e.productName} · ${e.quantityText}')
        .join('; ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                SellSubmission.statusLabel(submission.status),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: submission.status == 'pending'
                      ? Colors.orange.shade800
                      : Colors.green.shade800,
                ),
              ),
              const Spacer(),
              Text(when, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
