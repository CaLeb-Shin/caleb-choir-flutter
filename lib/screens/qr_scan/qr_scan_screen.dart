import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bottom_nav_bar.dart';
import '../../widgets/app_logo_title.dart';

class QrScanScreen extends StatefulWidget {
  final void Function(String code) onScanned;
  final String title;
  final String instruction;

  const QrScanScreen({
    super.key,
    required this.onScanned,
    this.title = 'QR 스캔',
    this.instruction = 'QR 코드를 카메라에 비춰주세요',
  });

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  // Restrict to QR format only and keep the detector running on every frame so
  // a code is recognised the instant it enters the viewfinder. Scanning all
  // barcode symbologies (the default) makes the decoder noticeably slower.
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 100,
  );
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppLogoTitle(
          title: widget.title,
          textStyle: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: const AppBottomNavBar(currentIndex: 3),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              final value = barcode?.rawValue;
              if (value == null || value.isEmpty) return;
              // Flip the guard synchronously before doing anything else so a
              // second detection frame can never fire the callback twice.
              _scanned = true;
              widget.onScanned(value);
              Navigator.pop(context);
            },
          ),
          // Overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.secondaryContainer,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          // Bottom instruction
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.instruction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
