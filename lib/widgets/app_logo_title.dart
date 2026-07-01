import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLogoTitle extends StatelessWidget {
  final String title;
  final TextStyle? textStyle;

  const AppLogoTitle({super.key, required this.title, this.textStyle});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: textStyle ?? AppText.headline(18),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
