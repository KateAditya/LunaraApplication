import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Centralised image caching for Lunara.
///
/// Two layers are in play and they do different jobs:
///
///  * **Disk cache** (`flutter_cache_manager`) — survives app restarts. Keeps
///    the encoded bytes on the device so a venue photo seen yesterday paints
///    without a network round-trip today.
///  * **Memory cache** (`PaintingBinding.instance.imageCache`) — holds *decoded*
///    images. Decoding is the expensive part while scrolling, but decoded frames
///    are huge (width × height × 4 bytes), which is why every call site should
///    pass a `memCacheWidth` sized to its layout slot.
///
/// Uploads are written with unique filenames (timestamp + random) on the
/// backend, so a replaced photo always arrives under a new URL. That means we
/// can cache aggressively without ever serving a stale image.
class LunaraImageCache {
  LunaraImageCache._();

  /// Cache bucket key on disk.
  static const String cacheKey = 'lunaraImageCache';

  /// How long an image may sit unused before it is eligible for cleanup.
  static const Duration stalePeriod = Duration(days: 14);

  /// Upper bound on files kept on disk. Combined with [maxDiskWidth] this keeps
  /// the on-device footprint in the low hundreds of MB worst case.
  static const int maxCacheObjects = 600;

  /// Images are downscaled to this width before being written to disk. Venue
  /// and party photos are frequently uploaded at 3000-4000px, which no phone
  /// screen can show — storing them at full size wastes disk and decode time.
  static const int maxDiskWidth = 1440;

  /// Ceiling for the decoded-image memory cache (~150 MiB). Flutter's default
  /// is 100 MiB; the bump buys smoother scrolling on image-dense screens while
  /// staying conservative enough for low-end Android devices.
  static const int maxMemoryCacheBytes = 150 << 20;

  /// Ceiling on the *number* of decoded images held in memory.
  static const int maxMemoryCacheCount = 400;

  static CacheManager? _manager;

  /// Shared disk cache manager used by every Lunara image widget.
  static CacheManager get manager {
    return _manager ??= CacheManager(
      Config(
        cacheKey,
        stalePeriod: stalePeriod,
        maxNrOfCacheObjects: maxCacheObjects,
        repo: JsonCacheInfoRepository(databaseName: cacheKey),
        fileService: HttpFileService(),
      ),
    );
  }

  /// Applies the in-memory decoded-image limits. Call once from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static void configure() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = maxMemoryCacheBytes;
    imageCache.maximumSize = maxMemoryCacheCount;
  }

  /// Converts a logical layout dimension into the pixel dimension an image
  /// should be decoded at, so a 96pt avatar never decodes as a 3000px bitmap.
  ///
  /// Returns `null` when [logicalSize] is absent or unbounded, which tells
  /// `cached_network_image` to decode at the source resolution.
  static int? decodeTarget(double? logicalSize, double devicePixelRatio) {
    if (logicalSize == null ||
        !logicalSize.isFinite ||
        logicalSize <= 0) {
      return null;
    }
    final target = (logicalSize * devicePixelRatio).round();
    return target > 0 ? target : null;
  }

  /// Removes a single URL from both the disk and memory caches.
  ///
  /// Not needed for ordinary photo replacement (new uploads get new URLs), but
  /// useful when a URL is known to have been overwritten server-side.
  static Future<void> evict(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await manager.removeFile(url);
    } catch (e) {
      debugPrint('[LunaraImageCache] evict(disk) failed for $url: $e');
    }
    try {
      await CachedNetworkImage.evictFromCache(url, cacheKey: cacheKey);
    } catch (e) {
      debugPrint('[LunaraImageCache] evict(memory) failed for $url: $e');
    }
  }

  /// Drops every decoded image from memory. Cheap and safe — the disk cache is
  /// untouched, so images repaint without hitting the network.
  static void clearMemory() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// Wipes the on-disk image cache entirely. Intended for logout and for a
  /// "clear cache" affordance in settings.
  static Future<void> clearAll() async {
    clearMemory();
    try {
      await manager.emptyCache();
    } catch (e) {
      debugPrint('[LunaraImageCache] clearAll failed: $e');
    }
  }

  /// Warms the disk cache for [urls] without painting them, so the next screen
  /// that shows these images renders immediately.
  ///
  /// Failures are swallowed per-URL: prefetching is best-effort by definition.
  static Future<void> prefetch(Iterable<String?> urls) async {
    final targets = urls
        .where((u) => u != null && u.isNotEmpty && u.startsWith('http'))
        .cast<String>()
        .toSet();
    if (targets.isEmpty) return;

    await Future.wait(
      targets.map((url) async {
        try {
          await manager.downloadFile(url);
        } catch (_) {
          // Best-effort only.
        }
      }),
    );
  }
}
