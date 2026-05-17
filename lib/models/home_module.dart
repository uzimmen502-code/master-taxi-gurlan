import 'package:flutter/material.dart';

/// Бош экрандаги битта модул карта тавсифи.
class HomeModule {
  const HomeModule({
    required this.id,
    required this.image,
    required this.label,
    required this.color1,
    required this.color2,
  });

  /// Идентификатор — ҳаракат бошқарувида ишлатилади.
  final String id;
  final String image;
  final String label;
  final Color color1;
  final Color color2;
}
