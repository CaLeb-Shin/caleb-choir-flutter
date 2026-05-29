import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _calebLogoAsset = 'assets/images/caleb_logo_mark_black.png';

class CalebLogoLoader extends StatefulWidget {
  const CalebLogoLoader({super.key, this.size = 96, this.loop = true});

  final double size;
  final bool loop;

  @override
  State<CalebLogoLoader> createState() => _CalebLogoLoaderState();
}

class _CalebLogoLoaderState extends State<CalebLogoLoader>
    with SingleTickerProviderStateMixin {
  static const _pieceSpecs = [
    _LogoPieceSpec(
      clip: Rect.fromLTRB(0, 0, 0.54, 0.43),
      begin: Offset(-0.56, -0.42),
      beginScale: 0.86,
    ),
    _LogoPieceSpec(
      clip: Rect.fromLTRB(0.43, 0, 1, 0.49),
      begin: Offset(0.58, -0.34),
      beginScale: 0.88,
    ),
    _LogoPieceSpec(
      clip: Rect.fromLTRB(0.25, 0.27, 0.76, 0.73),
      begin: Offset(0, -0.62),
      beginScale: 0.82,
    ),
    _LogoPieceSpec(
      clip: Rect.fromLTRB(0, 0.45, 0.54, 1),
      begin: Offset(-0.48, 0.5),
      beginScale: 0.9,
    ),
    _LogoPieceSpec(
      clip: Rect.fromLTRB(0.46, 0.43, 1, 1),
      begin: Offset(0.5, 0.46),
      beginScale: 0.9,
    ),
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.loop ? 1800 : 900),
    );
    _start();
  }

  @override
  void didUpdateWidget(covariant CalebLogoLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loop != widget.loop) {
      _controller.duration = Duration(milliseconds: widget.loop ? 1800 : 900);
      _start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final size = widget.size;

    if (disableAnimations) {
      return _StaticLogo(size: size);
    }

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value;
            final assembleT = widget.loop
                ? (phase <= 0.5 ? phase / 0.5 : 1.0)
                : phase;
            final eased = Curves.easeOutBack.transform(
              assembleT.clamp(0.0, 1.0),
            );
            final opacity = Curves.easeOut.transform(
              (assembleT / 0.35).clamp(0.0, 1.0),
            );
            final pulseT = widget.loop && phase > 0.5
                ? ((phase - 0.5) / 0.5).clamp(0.0, 1.0)
                : 0.0;
            final pulseScale = 1 + (0.018 * math.sin(pulseT * math.pi));
            final fullLogoOpacity = assembleT < 0.82
                ? 0.0
                : Curves.easeOut.transform(
                    ((assembleT - 0.82) / 0.18).clamp(0.0, 1.0),
                  );

            return Transform.scale(
              scale: pulseScale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final spec in _pieceSpecs)
                    _LogoPiece(
                      spec: spec,
                      progress: eased,
                      opacity: opacity,
                      extent: size,
                    ),
                  Opacity(opacity: fullLogoOpacity, child: const _LogoImage()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortestSide = constraints.biggest.shortestSide;
            final size = shortestSide.isFinite
                ? (shortestSide * 0.22).clamp(76.0, 116.0).toDouble()
                : 96.0;
            return CalebLogoLoader(size: size);
          },
        ),
      ),
    );
  }
}

class _LogoPiece extends StatelessWidget {
  const _LogoPiece({
    required this.spec,
    required this.progress,
    required this.opacity,
    required this.extent,
  });

  final _LogoPieceSpec spec;
  final double progress;
  final double opacity;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final offset = Offset.lerp(spec.begin, Offset.zero, progress)!;
    final scale = ui.lerpDouble(spec.beginScale, 1, progress)!;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: offset * extent,
        child: Transform.scale(
          scale: scale,
          child: ClipPath(
            clipper: _FractionalRectClipper(spec.clip),
            child: const _LogoImage(),
          ),
        ),
      ),
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _calebLogoAsset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class _StaticLogo extends StatelessWidget {
  const _StaticLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: size, child: const _LogoImage());
  }
}

class _FractionalRectClipper extends CustomClipper<Path> {
  const _FractionalRectClipper(this.rect);

  final Rect rect;

  @override
  Path getClip(Size size) {
    return Path()..addRect(
      Rect.fromLTRB(
        rect.left * size.width,
        rect.top * size.height,
        rect.right * size.width,
        rect.bottom * size.height,
      ),
    );
  }

  @override
  bool shouldReclip(_FractionalRectClipper oldClipper) {
    return oldClipper.rect != rect;
  }
}

class _LogoPieceSpec {
  const _LogoPieceSpec({
    required this.clip,
    required this.begin,
    required this.beginScale,
  });

  final Rect clip;
  final Offset begin;
  final double beginScale;
}
