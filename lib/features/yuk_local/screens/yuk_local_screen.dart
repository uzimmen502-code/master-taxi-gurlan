import 'package:flutter/material.dart';

import '../../profile/screens/profile_screen.dart';
import '../../yuk_shared/yuk_module_scaffold.dart';
import 'yuk_local_nearby_panel.dart';

/// «Туман ичида юк» модули — кириш экрани (moduleId `yuk_local`).
/// GPS асосида яқин юк машиналари каталоги.
class YukLocalScreen extends StatelessWidget {
  const YukLocalScreen({
    super.key,
    this.openPublish = false,
    this.highlightListingId,
  });

  /// «＋» → «Юк ташувчи»: очилиши билан янги эълон варағини кўрсатади.
  final bool openPublish;

  /// Пуш («муддати тугамоқда») ёки бош саҳифа қатори: шу эълон деталини очади.
  final String? highlightListingId;

  @override
  Widget build(BuildContext context) {
    return YukModuleScaffold(
      titleKey: 'home_module_yuk_local',
      builder: (context, owner, name) => YukLocalNearbyPanel(
        ownerId: owner.id,
        // Эълонга ХОМ исм ёзилади: `name` — экран учун «Сиз» fallback'и,
        // у бошқаларга эълон эгаси номи бўлиб кўринарди.
        ownerName: owner.name,
        ownerPhone: owner.phone,
        openPublishOnStart: openPublish,
        highlightListingId: highlightListingId,
        onRegister: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        ),
      ),
    );
  }
}
