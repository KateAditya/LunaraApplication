import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class LunaraNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final ColorFilter? colorFilter;

  const LunaraNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.colorFilter,
  });

  @override
  Widget build(BuildContext context) {
    final formattedUrl = ApiService.formatImageUrl(imageUrl);

    if (formattedUrl == null || formattedUrl.isEmpty) {
      return _buildFallback();
    }

    final isAsset = formattedUrl.startsWith('assets/');

    if (isAsset) {
      Widget image = Image.asset(
        formattedUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
      if (borderRadius != null) {
        image = ClipRRect(borderRadius: borderRadius!, child: image);
      }
      return image;
    }

    Widget image = CachedNetworkImage(
      imageUrl: formattedUrl,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
      errorWidget: (context, url, error) => errorWidget ?? _buildFallback(),
      imageBuilder: (context, imageProvider) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            image: DecorationImage(
              image: imageProvider,
              fit: fit,
              colorFilter: colorFilter,
            ),
          ),
        );
      },
    );

    if (borderRadius != null && colorFilter == null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LunaraTheme.electricViolet,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: Icon(Icons.nightlife_rounded, color: Colors.white38, size: 28),
      ),
    );
  }
}
