import 'package:flutter/material.dart';

import '../../../models/home_module.dart';

/// Бош экрандаги 3D-press анимацияли модул карта.
///
/// [isGrid] — `true` бўлса (десктоп grid): label пастда overlay, ўлчам ячейкага мос.
/// `false` — мобил: фикс баландлик, label йўқ (расм бутун карта).
class ModuleCard extends StatefulWidget {
  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
    this.isGrid = false,
  });

  final HomeModule module;
  final VoidCallback onTap;

  /// Grid режимида label пастда, расм `BoxFit.cover`.
  final bool isGrid;

  @override
  State<ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<ModuleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _translateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _translateAnim = Tween<double>(begin: -8.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();

  void _onTapUp(_) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final grid = widget.isGrid;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            // ignore: deprecated_member_use
            ..translate(0.0, _translateAnim.value)
            // ignore: deprecated_member_use
            ..scale(_scaleAnim.value),
          child: Material(
            elevation: 12 - _ctrl.value * 8,
            shadowColor: m.color1.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: grid
                  ? SizedBox.expand(child: _cardContent(m, grid))
                  : SizedBox(
                      height: 90,
                      child: _cardContent(m, grid),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardContent(HomeModule m, bool grid) {
    return Stack(
      fit: grid ? StackFit.expand : StackFit.loose,
      children: [
        Positioned.fill(
          child: Image.asset(
            m.image,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [m.color1, m.color2],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
        if (grid)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.58),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        if (grid)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              m.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.2,
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(
                    alpha: (0.6 - _ctrl.value * 0.5).clamp(0.0, 1.0),
                  ),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        if (_ctrl.value > 0)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: _ctrl.value * 0.08),
            ),
          ),
      ],
    );
  }
}
