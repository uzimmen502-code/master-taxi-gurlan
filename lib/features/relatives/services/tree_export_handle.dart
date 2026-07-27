import 'package:flutter/foundation.dart';

/// Дарахт экспортини AppBar overflow менюга улаш учун кўприк.
class TreeExportHandle extends ChangeNotifier {
  bool canExport = false;
  bool busy = false;

  Future<void> Function()? _gedcom;
  Future<void> Function()? _png;
  Future<void> Function()? _pdf;

  void bind({
    required bool canExport,
    required bool busy,
    required Future<void> Function() gedcom,
    required Future<void> Function() png,
    required Future<void> Function() pdf,
  }) {
    final changed = this.canExport != canExport || this.busy != busy;
    this.canExport = canExport;
    this.busy = busy;
    _gedcom = gedcom;
    _png = png;
    _pdf = pdf;
    if (changed) notifyListeners();
  }

  Future<void> exportGedcom() async => _gedcom?.call();
  Future<void> exportPng() async => _png?.call();
  Future<void> exportPdf() async => _pdf?.call();
}
