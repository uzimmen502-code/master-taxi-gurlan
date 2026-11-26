import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../data/family_links_repository.dart';
import '../screens/family_links_screen.dart';

/// Рўйхатдан ўтгандан кейинги БИР марталик таклиф (эга 2026-11-28, I): 3 тугма — «Турмуш ўртоғимни қўшаман»,
/// «Оила қурмаганман» (→ ота-она/ака-ука/опа-сингил изоҳи → қариндошлар), «Кейинроқ». Фақат дастур фаол бўлса.
/// Оилавий ҳолат ЁЗИЛМАЙДИ — қурилмада фақат «кўрсатилди» белгиси (ва кунига бир текширув).
const kFamilyPromptShownKey = 'family_prompt_shown_v1';
const kFamilyPromptCheckedKey = 'family_prompt_checked_day_v1';

/// Кўрсатиш керакми (тоза): аввал кўрсатилмаган, бугун текширилмаган.
bool familyPromptDue({required bool shown, required String checkedDay, required String today}) => !shown && checkedDay != today;

Future<void> maybeShowFamilyPrompt(BuildContext context, {FamilyLinksApi? api, DateTime? now}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final t = now ?? DateTime.now();
    final today = '${t.year}-${t.month}-${t.day}';
    if (!familyPromptDue(
        shown: prefs.getBool(kFamilyPromptShownKey) ?? false, checkedDay: prefs.getString(kFamilyPromptCheckedKey) ?? '', today: today)) {
      return;
    }
    await prefs.setString(kFamilyPromptCheckedKey, today);
    final a = api ?? FirebaseFamilyLinksApi();
    final s = await a.load();
    if (!s.anyProgramActive || s.spouse != null || !context.mounted) return;
    await prefs.setBool(kFamilyPromptShownKey, true);
    final choice = await showDialog<String>(context: context, builder: (_) => FamilyPromptDialog(state: s));
    if (!context.mounted || choice == null || choice == 'later') return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => FamilyLinksScreen(api: a, focus: choice)));
  } catch (e) {
    debugPrint('[Family] FAMILY_PROMPT_FAILED: $e');
  }
}

class FamilyPromptDialog extends StatefulWidget {
  const FamilyPromptDialog({super.key, required this.state});

  final FamilyState state;

  @override
  State<FamilyPromptDialog> createState() => _FamilyPromptDialogState();
}

class _FamilyPromptDialogState extends State<FamilyPromptDialog> {
  bool _single = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final amount = s.spouseProgram.active ? s.spouseProgram.amount : s.relativeProgram.amount;
    final title = _single
        ? context.tr('fam_prompt_single_title')
        : context.tr('fam_prompt_title').replaceAll('{amount}', formatMoney(amount));
    final body = _single ? context.tr('fam_prompt_single_body') : context.tr('fam_prompt_body');
    return AlertDialog(
      key: const ValueKey('fam_prompt'),
      title: Text(title),
      content: SingleChildScrollView(child: Text(body, key: const ValueKey('fam_prompt_body'))),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        if (!_single) ...[
          FilledButton(
            key: const ValueKey('fam_prompt_spouse'),
            onPressed: () => Navigator.pop(context, 'spouse'),
            child: Text(context.tr('fam_prompt_spouse')),
          ),
          OutlinedButton(
            key: const ValueKey('fam_prompt_single'),
            onPressed: () => setState(() => _single = true),
            child: Text(context.tr('fam_prompt_single')),
          ),
        ] else
          FilledButton(
            key: const ValueKey('fam_prompt_relatives'),
            onPressed: () => Navigator.pop(context, 'relatives'),
            child: Text(context.tr('fam_prompt_add_relatives')),
          ),
        TextButton(
          key: const ValueKey('fam_prompt_later'),
          onPressed: () => Navigator.pop(context, 'later'),
          child: Text(context.tr('fam_prompt_later')),
        ),
      ],
    );
  }
}

/// Профил ва «Яқин қариндошлар»даги кириш нуқтаси.
class FamilyLinksEntryTile extends StatelessWidget {
  const FamilyLinksEntryTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        key: const ValueKey('fam_entry'),
        minTileHeight: 48,
        leading: const Icon(Icons.family_restroom_rounded),
        title: Text(context.tr('fam_entry')),
        subtitle: Text(context.tr('fam_entry_sub')),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const FamilyLinksScreen())),
      );
}

/// Push / «Хабарлар»: 'family_invite' / 'family_link' → боғланишлар экрани; 'family_bonus' → супермаркет.
String? familyRouteOf(String type) => switch (type) {
      'family_invite' || 'family_link' => 'links',
      'family_bonus' => 'supermarket',
      _ => null,
    };
