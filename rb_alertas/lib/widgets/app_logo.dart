import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double? size;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const AppLogo({
    super.key,
    this.size,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final double finalWidth = size ?? width ?? 100;
    final double finalHeight = size ?? height ?? 100;

    Widget imageWidget = Image.asset(
      'assets/images/logo.png',
      width: finalWidth,
      height: finalHeight,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: finalWidth,
          height: finalHeight,
          decoration: BoxDecoration(
            color: const Color(0xFFE5EDFF),
            borderRadius: borderRadius ?? BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.shield,
            color: Color(0xFF1D61E7),
          ),
        );
      },
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
