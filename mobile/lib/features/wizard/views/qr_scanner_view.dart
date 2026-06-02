import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Simple QR scanner that pops with the first detected barcode's raw value.
///
/// The caller (typically the wizard server-url step) is responsible for
/// normalizing the returned string (e.g. enforcing port 2283) via
/// [WizardLogic.connectToServer].
class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final MobileScannerController _controller = MobileScannerController();
  bool _didScan = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_didScan) return;

    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;

    // Only accept Hearth Hub pairing payloads. The QR shown by the
    // backend is always `hearth://pair?host=<ip>&key=<token>`. Bare URLs
    // or arbitrary text are ignored so a stray QR poster on the wall
    // can't accidentally redirect the wizard.
    if (!value.startsWith('hearth://pair')) {
      debugPrint('[QrScanner] ignored non-hearth payload: "$value"');
      return;
    }

    _didScan = true;
    debugPrint('[QrScanner] hearth://pair detected, popping with payload');
    // Stop the camera before popping so the texture is released cleanly
    // even if the destination route takes a moment to appear.
    unawaited(_controller.stop());
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Hearth Hub")),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.black54,
              child: const Text(
                "Point your camera at the Hearth Hub QR code.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
