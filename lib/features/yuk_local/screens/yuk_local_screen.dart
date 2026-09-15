import 'package:flutter/material.dart';

import '../../yuk_shared/yuk_module_scaffold.dart';
import 'yuk_local_nearby_panel.dart';

/// «Туман ичида юк» модули — кириш экрани (moduleId `yuk_local`).
/// GPS асосида яқин юк машиналари каталоги.
class YukLocalScreen extends StatelessWidget {
  const YukLocalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return YukModuleScaffold(
      titleKey: 'home_module_yuk_local',
      builder: (context, owner, name) => YukLocalNearbyPanel(
        ownerId: owner.id,
        ownerName: name,
        ownerPhone: owner.phone,
      ),
    );
  }
}
