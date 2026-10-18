import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Кабинет экранининг кўриниш бўлаклари (UI/UX қайта лойиҳаси, 2026-10-18).
///
/// Бу ерда ФАҚАТ кўриниш: маълумот ва ҳаракатлар (`onTap`) чақирувчидан
/// келади, шунинг учун Firebase'сиз синаш мумкин. Рангларнинг ҳаммаси
/// `context.ava` токенларидан — қаттиқ ёзилган ранг йўқ.

/// Бренд ҳедери: аватар, исм, телефон, роль чипи ва ихтиёрий [footer]
/// (ҳайдовчи индикатори). AppBar билан бир хил рангда — иккита тус
/// «қават» бўлиб кўринмайди.
class CabinetHeader extends StatelessWidget {
  const CabinetHeader({
    super.key,
    required this.avatar,
    required this.title,
    required this.roleLabel,
    required this.changePhotoLabel,
    required this.onAvatarTap,
    this.phone = '',
    this.onRoleTap,
    this.footer,
  });

  /// Доира ичидаги расм (ёки бош ҳарф).
  final Widget avatar;
  final String title;
  final String phone;
  final String roleLabel;

  /// Аватарнинг экран ўқувчи учун ёрлиғи («Расмни ўзгартириш»).
  final String changePhotoLabel;
  final VoidCallback onAvatarTap;

  /// Яширин тезкор амал (7 марта босиш) — кўринишда оддий чип.
  final VoidCallback? onRoleTap;
  final Widget? footer;

  static const double _avatarSize = 92;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      color: c.brand,
      padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 4, AvaSpace.screen, 30),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: changePhotoLabel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAvatarTap,
              child: SizedBox(
                width: _avatarSize + 8,
                height: _avatarSize + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        width: _avatarSize,
                        height: _avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surface,
                          border: Border.all(color: c.surface, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 14,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipOval(child: avatar),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c.ink,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.brand, width: 2),
                        ),
                        child: Icon(Icons.photo_camera_rounded, size: 16, color: c.surface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: c.brandInk,
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              phone,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.brandInk.withValues(alpha: 0.78),
              ),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onRoleTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(AvaRadius.chip),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.brandInk,
                ),
              ),
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// «Ҳамён» герои: тўқ карточка, йирик баланс, «Тўлдириш» тугмаси.
///
/// Ҳедер билан ярмигача қоплашади: орқасидаги фон тепа ярмида бренд,
/// пастки ярмида экран фони (градиент, қаттиқ чегара) — шунда карточка
/// ҳедер устида «сузиб» турган кўринади, `Transform` билан сурилмайди
/// (унда жой қолиб кетар эди ва босиш майдони силжирди).
class CabinetWalletCard extends StatelessWidget {
  const CabinetWalletCard({
    super.key,
    required this.title,
    required this.balanceText,
    required this.hint,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;

  /// `null` — баланс номаълум (юкланмаган/хато): ёлғон «0» кўрсатилмайди,
  /// ўрнига [hint] чиқади.
  final String? balanceText;
  final String hint;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final known = balanceText != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.5, 0.5],
          colors: [c.brand, c.bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AvaSpace.screen),
        child: Semantics(
          button: true,
          label: known ? '$title $balanceText' : '$title $hint',
          child: ExcludeSemantics(
            child: Material(
              color: c.ink,
              borderRadius: BorderRadius.circular(20),
              elevation: 6,
              shadowColor: const Color(0x55000000),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.account_balance_wallet_rounded,
                                    size: 16, color: c.brand),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: c.surface.withValues(alpha: 0.72),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              known ? balanceText! : hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: known ? 26 : 15,
                                height: 1.15,
                                fontWeight: known ? FontWeight.w800 : FontWeight.w600,
                                color: c.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        constraints: const BoxConstraints(minHeight: AvaTap.minSize),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.brand,
                          borderRadius: BorderRadius.circular(AvaRadius.chip),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 18, color: c.brandInk),
                            const SizedBox(width: 2),
                            Text(
                              actionLabel,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: c.brandInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Бўлим: кичик сарлавҳа + битта юмалоқ юзада қаторлар (орасида чизиқ).
class CabinetSection extends StatelessWidget {
  const CabinetSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, indent: 68, color: c.line));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 18, AvaSpace.screen, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: c.ink2,
                ),
              ),
            ),
          ),
          Material(
            color: c.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(18),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
  }
}

/// Бўлим қатори: юмшоқ иконка чипи, сарлавҳа, изоҳ, `›`.
/// [danger] — қайтарилмас/чиқиш амали (қизил).
class CabinetRow extends StatelessWidget {
  const CabinetRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final accent = danger ? c.danger : c.brandText;
    final chip = danger ? c.dangerSoft : c.brandSoft;
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    return Semantics(
      button: true,
      label: hasSub ? '$title. $subtitle' : title,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: chip,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 21, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: danger ? c.danger : c.ink,
                          ),
                        ),
                        if (hasSub) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, height: 1.25, color: c.ink2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showChevron) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: c.ink3),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Диққат баннери (масалан «Манзил тўлдирилмаган») — амал тугмаси билан.
class CabinetNotice extends StatelessWidget {
  const CabinetNotice({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 14, AvaSpace.screen, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: c.warnSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.warn.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_rounded, color: c.warn, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, height: 1.3, color: c.ink),
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(AvaTap.minSize, AvaTap.minSize),
                foregroundColor: c.warn,
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
