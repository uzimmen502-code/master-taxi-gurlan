import 'package:flutter/material.dart';

/// Chip tanlanganda route kartada qisqa pulse (Phase T).
class MarshrutPulsingRouteCard extends StatefulWidget {
  const MarshrutPulsingRouteCard({
    super.key,
    required this.pulseToken,
    required this.child,
  });

  final int pulseToken;
  final Widget child;

  @override
  State<MarshrutPulsingRouteCard> createState() =>
      _MarshrutPulsingRouteCardState();
}

class _MarshrutPulsingRouteCardState extends State<MarshrutPulsingRouteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.025), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.025, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant MarshrutPulsingRouteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseToken != oldWidget.pulseToken && widget.pulseToken > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
