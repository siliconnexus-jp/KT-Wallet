import 'package:flutter/material.dart';

/// Bundled offline identity. Never loads a remote image on the signer.
class SignerBrandMark extends StatelessWidget {
  const SignerBrandMark({super.key, this.size = 88});

  static const asset = 'assets/brand/app_icon.png';
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.26),
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
    ),
  );
}
