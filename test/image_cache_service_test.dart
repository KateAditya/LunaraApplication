import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:lunara_app/services/image_cache_service.dart';

/// Compile-time proof that [LunaraCacheManager] still satisfies
/// [ImageCacheManager]. If the mixin is ever dropped, this assignment fails to
/// compile rather than failing silently at runtime.
///
/// It matters because `cached_network_image` only honours `maxWidthDiskCache`
/// when the manager implements that interface: it asserts on the mismatch,
/// which throws in debug builds (images simply never appear on device) and
/// quietly ignores the resizing in release builds.
// ignore: unused_element
ImageCacheManager _proofOfImageCacheManager(LunaraCacheManager m) => m;

void main() {
  group('LunaraImageCache.decodeTarget', () {
    test('scales a logical size by the device pixel ratio', () {
      expect(LunaraImageCache.decodeTarget(120, 3.0), 360);
      expect(LunaraImageCache.decodeTarget(48, 2.0), 96);
    });

    test('returns null for absent or unbounded sizes so the source size is kept', () {
      expect(LunaraImageCache.decodeTarget(null, 3.0), isNull);
      expect(LunaraImageCache.decodeTarget(double.infinity, 3.0), isNull);
      expect(LunaraImageCache.decodeTarget(0, 3.0), isNull);
      expect(LunaraImageCache.decodeTarget(-10, 3.0), isNull);
    });
  });
}
