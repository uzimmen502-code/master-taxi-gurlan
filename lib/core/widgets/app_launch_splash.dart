import 'package:flutter/material.dart';

/// Native splash dan keyin: birinchi frame gacha to'liq [splash_full] (o'tish uzilmasin).
class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({super.key, required this.child});

  final Widget child;

  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible)
            const Positioned.fill(
              child: IgnorePointer(
                child: Image(
                  image: AssetImage('assets/images/splash_full.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
