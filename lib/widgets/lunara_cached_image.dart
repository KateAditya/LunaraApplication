import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/image_cache_service.dart';

/// Drop-in replacement for `Image.network` that caches to disk and decodes at
/// display size.
///
/// The constructor deliberately mirrors `Image.network`'s signature — same
/// positional URL, same `errorBuilder` and `loadingBuilder` shapes — so an
/// existing call site migrates by changing the constructor name and nothing
/// else.
///
/// What it adds over `Image.network`:
///
///  * a persistent **disk cache**, so images survive app restarts,
///  * **decode-at-display-size**, so a 4000px photo in a 120pt tile costs
///    ~0.2 MB of RAM instead of ~64 MB,
///  * relative-path handling via [ApiService.formatImageUrl],
///  * transparent support for local `assets/` paths, which some records carry.
///
/// See [LunaraImageCache] for the cache configuration itself.
class LunaraCachedImage extends StatelessWidget {
  /// Raw URL or path. May be absolute, server-relative, or an `assets/` path.
  final String? url;

  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  /// Matches `Image.network`'s `errorBuilder`. The `StackTrace` is always null —
  /// the underlying loader does not surface one.
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)? errorBuilder;

  /// Matches `Image.network`'s `loadingBuilder`. While bytes are in flight this
  /// is called with a non-null [ImageChunkEvent]; callers that early-return on
  /// `progress == null` keep working unchanged.
  final Widget Function(BuildContext context, Widget child, ImageChunkEvent? progress)? loadingBuilder;

  /// Explicit decode width in pixels. Overrides the value derived from [width].
  final int? cacheWidth;

  /// Explicit decode height in pixels. Overrides the value derived from [height].
  final int? cacheHeight;

  /// Convenience rounding, so call sites can drop a wrapping [ClipRRect].
  final BorderRadius? borderRadius;

  const LunaraCachedImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.loadingBuilder,
    this.cacheWidth,
    this.cacheHeight,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim() ?? '';

    // `blob:` (web object URLs) and `data:` (inline bytes) are already local and
    // have no stable identity to cache against, so they bypass the cache
    // entirely. They must also skip formatImageUrl, which would otherwise
    // prefix them with the API base URL.
    if (raw.startsWith('blob:') || raw.startsWith('data:')) {
      return _round(
        Image.network(
          raw,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          errorBuilder: (context, error, stackTrace) => _error(context, error, stackTrace),
          loadingBuilder: loadingBuilder,
        ),
      );
    }

    final resolved = ApiService.formatImageUrl(raw);

    if (resolved == null || resolved.isEmpty) {
      return _round(_error(context, 'Empty image URL'));
    }

    // Some records store bundled asset paths rather than remote URLs.
    if (resolved.startsWith('assets/')) {
      return _round(
        Image.asset(
          resolved,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          errorBuilder: (context, error, stackTrace) => _error(context, error, stackTrace),
        ),
      );
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

    return _round(
      CachedNetworkImage(
        imageUrl: resolved,
        cacheManager: LunaraImageCache.manager,
        cacheKey: resolved,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        // Decode only as many pixels as this slot can actually show.
        memCacheWidth: cacheWidth ?? LunaraImageCache.decodeTarget(width, dpr),
        memCacheHeight: cacheHeight ?? LunaraImageCache.decodeTarget(height, dpr),
        maxWidthDiskCache: LunaraImageCache.maxDiskWidth,
        // A cached image should appear instantly; only a genuine network fetch
        // gets a fade, and callers can still see progress via loadingBuilder.
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholderFadeInDuration: Duration.zero,
        errorWidget: (context, _, error) => _error(context, error),
        progressIndicatorBuilder: loadingBuilder == null
            ? null
            : (context, _, progress) => loadingBuilder!(
                  context,
                  const SizedBox.shrink(),
                  ImageChunkEvent(
                    cumulativeBytesLoaded: progress.downloaded,
                    expectedTotalBytes: progress.totalSize,
                  ),
                ),
      ),
    );
  }

  Widget _round(Widget child) {
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }

  Widget _error(BuildContext context, Object error, [StackTrace? stackTrace]) {
    if (errorBuilder != null) {
      return errorBuilder!(context, error, stackTrace);
    }
    return _defaultError();
  }

  Widget _defaultError() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 28),
      ),
    );
  }
}
