import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../profile/screens/profile_screen.dart';
import '../domain/favorite_ref.dart';
import '../favorites_controller.dart';

/// Меҳмон (телефонсиз) юракни босганда — мавжуд «рўйхатдан ўтинг» чақируви (deal chat билан бир хил шакл):
/// SnackBar + «Кабинетга ўтиш» → [ProfileScreen].
void showFavoriteGuestPrompt(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    key: const ValueKey('fav_guest_prompt'),
    content: Text(context.tr('fav_login_required')),
    action: SnackBarAction(
      label: context.tr('fav_login_cta'),
      onPressed: () => navigator.push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
    ),
  ));
}

/// Босиш натижасини фойдаланувчига кўрсатиш (меҳмон → чақирув, хато → умумий хабар).
Future<void> toggleFavoriteWithFeedback(BuildContext context, FavoriteRef ref, {FavoritesController? controller}) async {
  final c = controller ?? FavoritesController.instance;
  final messenger = ScaffoldMessenger.of(context);
  final failedText = context.tr('fav_toggle_failed');
  final outcome = await c.toggle(ref);
  if (!context.mounted) return;
  switch (outcome) {
    case FavoriteToggleOutcome.guest:
      showFavoriteGuestPrompt(context);
    case FavoriteToggleOutcome.failed:
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
    case FavoriteToggleOutcome.added:
    case FavoriteToggleOutcome.removed:
    case FavoriteToggleOutcome.busy:
    case FavoriteToggleOutcome.invalid:
      break;
  }
}

/// ❤ тугмаси — карточка расми устида ([overlay] = true, ярим шаффоф доира) ёки детал AppBar'ида.
/// Ҳолат — ягона [FavoritesController]дан (алоҳида ўқиш йўқ).
class FavoriteHeart extends StatefulWidget {
  const FavoriteHeart({
    super.key,
    required this.favorite,
    this.overlay = true,
    this.size = 20,
    this.controller,
  });

  final FavoriteRef favorite;
  final bool overlay;
  final double size;

  /// Тест учун; бўлмаса [FavoritesController.instance].
  final FavoritesController? controller;

  @override
  State<FavoriteHeart> createState() => _FavoriteHeartState();
}

class _FavoriteHeartState extends State<FavoriteHeart> {
  FavoritesController get _c => widget.controller ?? FavoritesController.instance;

  @override
  void initState() {
    super.initState();
    _c.ensureStarted();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.favorite.key;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final on = _c.isFavorite(key);
        final icon = Icon(
          on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: widget.size,
          color: on ? AvaLight.danger : (widget.overlay ? Colors.white : null),
        );
        return Semantics(
          button: true,
          toggled: on,
          label: context.tr(on ? 'fav_remove' : 'fav_add'),
          child: widget.overlay
              ? InkResponse(
                  key: ValueKey('fav_heart_$key'),
                  radius: 20,
                  onTap: () => toggleFavoriteWithFeedback(context, widget.favorite, controller: _c),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                    child: icon,
                  ),
                )
              : IconButton(
                  key: ValueKey('fav_heart_$key'),
                  tooltip: context.tr(on ? 'fav_remove' : 'fav_add'),
                  onPressed: () => toggleFavoriteWithFeedback(context, widget.favorite, controller: _c),
                  icon: icon,
                ),
        );
      },
    );
  }
}

/// Грид карточка расми Stack'ида ПАСТКИ ЎНГ бурчак: тепа ўнгда бозор белгиси/видео, пастки чапда
/// [MarketLocationPill] (у ўнгда 40 px жой қолдиради) — устма-уст тушмайди.
class FavoriteHeartOverlay extends StatelessWidget {
  const FavoriteHeartOverlay({super.key, required this.favorite});

  final FavoriteRef favorite;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 4,
      bottom: 4,
      child: FavoriteHeart(favorite: favorite),
    );
  }
}
