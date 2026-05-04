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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor,
        child: url == null || url.isEmpty
            ? Icon(Icons.church_rounded, color: iconColor, size: size * 0.5)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.church_rounded,
                  color: iconColor,
                  size: size * 0.5,
                ),
              ),
      ),
    );
  }
}
