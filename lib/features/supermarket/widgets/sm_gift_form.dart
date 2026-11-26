import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/sm_holiday.dart';

/// Совға блоки (эга 2026-11-26): «Совға сифатида юбориш» → қабул қилувчи исми, телефони, қисқа табрик (≤ 200).
/// Нарх доим яширин. Текширув — [smGiftProblems] (сервер ҳам текширади).
class SmGiftSection extends StatelessWidget {
  const SmGiftSection({
    super.key,
    required this.asGift,
    required this.onToggle,
    required this.name,
    required this.phone,
    required this.message,
    required this.onChanged,
    this.showErrors = false,
  });

  final bool asGift;
  final ValueChanged<bool> onToggle;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController message;
  final VoidCallback onChanged;
  final bool showErrors;

  SmGift get gift => SmGift(recipientName: name.text, recipientPhone: phone.text, message: message.text);

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final problems = asGift ? smGiftProblems(gift).toSet() : const <String>{};
    String? err(String k) => showErrors && problems.contains(k) ? context.tr(k) : null;
    return Column(
      key: const ValueKey('sm_gift_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('sm_gift_toggle'),
          contentPadding: EdgeInsets.zero,
          value: asGift,
          onChanged: onToggle,
          title: Text(context.tr('sm_gift_toggle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
          subtitle: Text(context.tr('sm_gift_toggle_hint'), style: TextStyle(fontSize: 14, color: c.ink2)),
        ),
        if (asGift) ...[
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('sm_gift_name'),
            controller: name,
            onChanged: (_) => onChanged(),
            maxLength: kSmGiftNameMax,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: context.tr('sm_gift_name'),
              errorText: err('sm_gift_err_name'),
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sm_gift_phone'),
            controller: phone,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\s()-]'))],
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: context.tr('sm_gift_phone'),
              hintText: '+998 90 123 45 67',
              errorText: err('sm_gift_err_phone'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sm_gift_message'),
            controller: message,
            onChanged: (_) => onChanged(),
            maxLength: kSmGiftMessageMax,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: context.tr('sm_gift_message'),
              errorText: err('sm_gift_err_message'),
              border: const OutlineInputBorder(),
            ),
          ),
          Container(
            key: const ValueKey('sm_gift_info'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.card_giftcard_rounded, color: c.brandText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('sm_gift_info'), style: TextStyle(fontSize: 14, color: c.ink)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Етказиш санаси: сервер оралиқ берган кунлар, бугундан 14 кунгача (горизонтал чиплар; катта шрифтда баландлиги
/// ўсади).
class SmDeliveryDatePicker extends StatelessWidget {
  const SmDeliveryDatePicker({
    super.key,
    required this.today,
    required this.dates,
    required this.selected,
    required this.onSelected,
  });

  final DateTime today;
  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  String _label(BuildContext context, DateTime d) {
    final diff = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (diff == 0) return context.tr('sm_day_today');
    if (diff == 1) return context.tr('sm_day_tomorrow');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('sm_delivery_dates'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in dates) ...[
            ChoiceChip(
              key: ValueKey('sm_date_${smIsoDate(d)}'),
              label: Text(_label(context, d), style: const TextStyle(fontSize: 15)),
              selected: smIsoDate(d) == smIsoDate(selected),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelected(d),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
