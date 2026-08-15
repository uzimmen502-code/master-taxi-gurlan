import 'package:flutter/material.dart';

import '../../../core/navigation/app_route_observer.dart';

/// Видео фақат жорий экран + илова актив бўлганда ўйнасин.
mixin TvScreenPlayback<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver, RouteAware {
  bool tvScreenActive = true;
  bool tvAppActive = true;
  ModalRoute<void>? _tvRoute;

  bool get tvCanPlay => tvScreenActive && tvAppActive && mounted;

  void tvOnPlaybackBlocked();
  void tvOnPlaybackAllowed();

  void tvBindPlayback() {
    WidgetsBinding.instance.addObserver(this);
  }

  void tvUnbindPlayback() {
    if (_tvRoute != null) {
      appRouteObserver.unsubscribe(this);
      _tvRoute = null;
    }
    WidgetsBinding.instance.removeObserver(this);
  }

  void tvSubscribeRoute() {
    final route = ModalRoute.of(context);
    if (identical(route, _tvRoute)) return;
    if (_tvRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _tvRoute = route;
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == tvAppActive) return;
    tvAppActive = active;
    if (active) {
      if (tvCanPlay) tvOnPlaybackAllowed();
    } else {
      tvOnPlaybackBlocked();
    }
  }

  @override
  void didPushNext() {
    tvScreenActive = false;
    tvOnPlaybackBlocked();
  }

  @override
  void didPopNext() {
    tvScreenActive = true;
    if (tvCanPlay) tvOnPlaybackAllowed();
  }
}
