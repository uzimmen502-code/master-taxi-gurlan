import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/locale_utils.dart';
import 'l10n_extension.dart';
import 'locale_notifier.dart';

/// Til tanlash natijasi.
enum LanguagePickerChoice {
  uzCyrl,
  uzLatn,
  ru,
  followDevice,
}

extension LanguagePickerChoiceLocale on LanguagePickerChoice {
  Locale? get locale => switch (this) {
        LanguagePickerChoice.uzCyrl => LocaleUtils.uzCyrl,
        LanguagePickerChoice.uzLatn => LocaleUtils.uzLatn,
        LanguagePickerChoice.ru => LocaleUtils.ru,
        LanguagePickerChoice.followDevice => null,
      };
}

/// Umumiy til tanlash bottom sheet (profil, intercity, ...).
Future<LanguagePickerChoice?> showLanguagePickerSheet(
  BuildContext context, {
  bool includeFollowDevice = true,
}) {
  return showModalBottomSheet<LanguagePickerChoice>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              context.tr('language'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: Text(context.tr('lang_uz_cyrl')),
            onTap: () => Navigator.pop(ctx, LanguagePickerChoice.uzCyrl),
          ),
          ListTile(
            title: Text(context.tr('lang_uz_latn')),
            onTap: () => Navigator.pop(ctx, LanguagePickerChoice.uzLatn),
          ),
          ListTile(
            title: Text(context.tr('lang_ru')),
            onTap: () => Navigator.pop(ctx, LanguagePickerChoice.ru),
          ),
          if (includeFollowDevice)
            ListTile(
              leading: const Icon(Icons.smartphone_outlined),
              title: Text(context.tr('lang_follow_device')),
              subtitle: Text(
                context.tr('lang_follow_device_sub'),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, LanguagePickerChoice.followDevice),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Tanlovni `LocaleNotifier` ga qo'llash.
Future<void> applyLanguagePickerChoice(
  BuildContext context,
  LanguagePickerChoice choice,
) async {
  final notifier = context.read<LocaleNotifier>();
  // ignore: use_build_context_synchronously — Provider read above
  if (choice == LanguagePickerChoice.followDevice) {
    await notifier.setFollowDeviceLocale();
  } else {
    final loc = choice.locale;
    if (loc != null) await notifier.setLocale(loc);
  }
}
