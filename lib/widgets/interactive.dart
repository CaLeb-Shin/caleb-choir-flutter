import 'package:flutter/material.dart';

/// 호버 시 약간 확대 + 그림자 효과, 클릭 시 축소 피드백을 주는 위젯
class Tappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double hoverScale;
  final double tapScale;
  final BorderRadius? borderRadius;

  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.hoverScale = 1.02,
    this.tapScale = 0.97,
    this.borderRadius,
  });

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  bool _pressing = false;

  double get _scale {
    if (_pressing) return widget.tapScale;
    if (_hovering) return widget.hoverScale;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() { _hovering = false; _pressing = false; }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(14),
              boxShadow: _hovering && widget.onTap != null
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4))]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 호버 시 배경색 변하는 버튼 래퍼
class HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? hoverColor;
  final BorderRadius borderRadius;

  const HoverButton({
    super.key,
    required this.child,
    this.onTap,
    this.hoverColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovering ? (widget.hoverColor ?? Colors.black.withValues(alpha: 0.03)) : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
