import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/locale_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/locale_utils.dart';

/// Profil — til tanlash (Kirill / Lotin / Rus).
class LanguageSettingsTile extends StatelessWidget {
  const LanguageSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final current = Localizations.localeOf(context);
    final subtitle = _labelFor(current, context);

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
  }

  String _labelFor(Locale locale, BuildContext context) {
    if (locale.languageCode == 'ru') return context.tr('lang_ru');
    if (locale.scriptCode == 'Latn') return context.tr('lang_uz_latn');
    return context.tr('lang_uz_cyrl');
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final chosen = await showModalBottomSheet<Locale>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr('lang_uz_cyrl')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.uzCyrl),
            ),
            ListTile(
              title: Text(context.tr('lang_uz_latn')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.uzLatn),
            ),
            ListTile(
              title: Text(context.tr('lang_ru')),
              onTap: () => Navigator.pop(ctx, LocaleUtils.ru),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await context.read<LocaleNotifier>().setLocale(chosen);
  }
}
