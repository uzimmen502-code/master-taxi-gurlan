import 'package:flutter/material.dart';

import '../../yuk_shared/yuk_module_scaffold.dart';
import 'yuk_intercity_board.dart';

/// «Шаҳарлараро юк» модули — кириш экрани (moduleId `yuk_intercity`).
/// Cargo/truck эълонлар доскаси.
///
/// [highlightListingId] — push/search'дан келган эълон рўйхат тепасига
/// чиқарилади; [autoFrom]/[autoTo] — search'дан маршрут фильтри.
class YukIntercityScreen extends StatelessWidget {
  const YukIntercityScreen({
    super.key,
    this.highlightListingId,
    this.autoFrom,
    this.autoTo,
  });

  final String? highlightListingId;
  final String? autoFrom;
  final String? autoTo;

  @override
  Widget build(BuildContext context) {
    return YukModuleScaffold(
      titleKey: 'home_module_yuk_intercity',
      builder: (context, owner, name) => YukIntercityBoard(
        ownerId: owner.id,
        ownerName: name,
        ownerPhone: owner.phone,
        highlightListingId: highlightListingId,
        autoFrom: autoFrom,
        autoTo: autoTo,
      ),
    );
  }
}
