import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../qr_login_codes.dart';

/// Телефон: компьютер экранидаги AVA кириш QR'ини сканерлаш (`mobile_scanner`, фақат QR формат).
/// Натижа — `sid` (AVA QR бўлмаса қайтарилмайди, огоҳлантириш кўрсатилади).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  DateTime _lastWarn = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final sid = parseQrLoginPayload(b.rawValue);
      if (sid.isNotEmpty) {
        _done = true;
        unawaited(_controller.stop());
        Navigator.of(context).pop(sid);
        return;
      }
    }
    final now = DateTime.now();
    if (now.difference(_lastWarn) > const Duration(seconds: 3)) {
      _lastWarn = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('qrl_scan_not_ava'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(context.tr('qrl_scan_title'))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr(error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'qrl_camera_denied'
                      : 'qrl_err_generic'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              context.tr('qrl_scan_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
