import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLogoTitle extends StatelessWidget {
  final String title;
  final TextStyle? textStyle;
  final double logoSize;

  const AppLogoTitle({
    super.key,
    required this.title,
    this.textStyle,
    this.logoSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/images/icon.png',
            width: logoSize,
            height: logoSize,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: textStyle ?? AppText.headline(18),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
