import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/language_picker_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/locale_utils.dart';

/// Profil — til tanlash (Kirill / Lotin / Rus / qurilma).
class LanguageSettingsTile extends StatelessWidget {
  const LanguageSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: LocaleUtils.hasManualLocale(),
      builder: (context, snap) {
        final manual = snap.data ?? true;
        final current = Localizations.localeOf(context);
        final subtitle = manual
            ? _labelFor(current, context)
            : '${context.tr('lang_follow_device')} · ${_labelFor(current, context)}';

        return ListTile(
          leading: const Icon(Icons.language, color: AppColors.primary),
          title: Text(context.tr('language')),
          subtitle: Text(
            '${context.tr('language_subtitle')}\n$subtitle',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickLanguage(context),
        );
      },
    );
  }

  String _labelFor(Locale locale, BuildContext context) {
    if (locale.languageCode == 'ru') return context.tr('lang_ru');
    if (locale.scriptCode == 'Latn') return context.tr('lang_uz_latn');
    return context.tr('lang_uz_cyrl');
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final chosen = await showLanguagePickerSheet(context);
    if (chosen == null || !context.mounted) return;
    await applyLanguagePickerChoice(context, chosen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('language_changed'))),
    );
  }
}
