import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ChurchLogo extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;

  const ChurchLogo({
    super.key,
    this.imageUrl,
    this.size = 40,
    this.radius = 12,
    this.backgroundColor = AppColors.primarySoft,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    Widget fallbackIcon() {
      return Icon(Icons.church_rounded, color: iconColor, size: size * 0.5);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        child: hasImage
            ? Padding(
                padding: EdgeInsets.all(size * 0.12),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return fallbackIcon();
                  },
                  errorBuilder: (context, error, stackTrace) => fallbackIcon(),
                ),
              )
            : fallbackIcon(),
      ),
    );
  }
}
