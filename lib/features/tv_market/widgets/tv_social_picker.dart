import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../services/tv_social.dart';

/// Роликни AVA расмий ижтимоий тармоқларига ҳам юбориш танлови.
/// Тармоқ танланса — «Рухсат бераман» белгиси (7-босқич): нима ва қаерга очиқ
/// жойланиши аниқ ёзилади; белгиланмаса жойлаш тўхтатилади.
///
/// [sellerChannel] (`@nom`, 2026-10-25) берилса — сотувчининг ЎЗ Telegram канали «Менинг каналим» чипи ҳам
/// кўринади; ўша битта белги уни ҳам қамрайди ва матн канални номи билан айтади.
class TvSocialPicker extends StatelessWidget {
  const TvSocialPicker({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.consent,
    required this.onConsent,
    this.sellerChannel = '',
  });

  final Set<String> selected;
  final void Function(String id, bool on) onToggle;
  final bool consent;
  final ValueChanged<bool> onConsent;
  final String sellerChannel;

  @override
  Widget build(BuildContext context) {
    final showSeller = sellerChannel.isNotEmpty;
    final avaNames = [
      for (final id in TvSocial.ordered)
        if (selected.contains(id)) context.tr(TvSocial.labelKey(id)),
    ];
    final sellerPicked = showSeller && selected.contains(TvSocial.sellerTelegram);
    final consentText = [
      if (avaNames.isNotEmpty) context.tr('tv_social_consent_check').replaceAll('{networks}', avaNames.join(', ')),
      if (sellerPicked) context.tr('tv_social_consent_check_own').replaceAll('{channel}', sellerChannel),
    ].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('tv_social_title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('tv_social_hint'),
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in TvSocial.ordered)
              FilterChip(
                label: Text(context.tr(TvSocial.labelKey(id))),
                selected: selected.contains(id),
                onSelected: (on) => onToggle(id, on),
              ),
            if (showSeller)
              FilterChip(
                key: const ValueKey('tv_social_seller_telegram'),
                avatar: const Icon(Icons.send_rounded, size: 16),
                label: Text('${context.tr(TvSocial.labelKey(TvSocial.sellerTelegram))} $sellerChannel'),
                selected: sellerPicked,
                onSelected: (on) => onToggle(TvSocial.sellerTelegram, on),
              ),
          ],
        ),
        if (consentText.isNotEmpty)
          CheckboxListTile(
            key: const ValueKey('tv_social_consent'),
            value: consent,
            onChanged: (v) => onConsent(v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(consentText, style: const TextStyle(fontSize: 14)),
          ),
      ],
    );
  }
}
