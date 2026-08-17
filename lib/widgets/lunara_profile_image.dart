import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../screens/profile/profile_screen.dart';
import '../services/api_service.dart';

class LunaraProfileImage extends StatelessWidget {
  final User? user;
  final Map<dynamic, dynamic>? userData;
  final double radius;
  final bool showGradientBorder;
  final bool isInteractive;
  final double borderWidth;

  /// Override tier for callers that pass `userData` (Map-based) without a full User object.
  /// Set to 'PRO' or 'ELITE' to show the golden ring even from raw map data.
  final String? overrideTier;

  const LunaraProfileImage({
    super.key,
    this.user,
    this.userData,
    this.radius = 24,
    this.showGradientBorder = true,
    this.isInteractive = true,
    this.borderWidth = 2,
    this.overrideTier,
  });

  User? get _resolvedUser {
    if (user != null) return user;
    if (userData != null) {
      try {
        return User.fromJson(Map<String, dynamic>.from(userData!));
      } catch (e) {
        debugPrint('Error resolving user in LunaraProfileImage: $e');
        return null;
      }
    }
    return null;
  }

  String? get _profilePhoto {
    final resolved = _resolvedUser;
    final fromResolved = resolved?.profilePhoto;
    if (fromResolved != null && fromResolved.trim().isNotEmpty && fromResolved != 'null') return fromResolved;

    if (userData != null) {
      String? photo =
          (userData!['profilePhotoUrl'] ??
                  userData!['profileImageUrl'] ??
                  userData!['photoUrl'] ??
                  userData!['profilePhoto'] ??
                  userData!['hostProfilePhotoUrl'] ??
                  userData!['hostPhotoUrl'] ??
                  userData!['senderImage'] ??
                  userData!['senderPhoto'] ??
                  userData!['imageUrl'] ??
                  userData!['userAvatar'] ??
                  userData!['image'] ??
                  userData!['photo'] ??
                  userData!['avatar'])
              ?.toString();

      if (photo != null &&
          photo.trim().isNotEmpty &&
          photo != 'null' &&
          photo != 'undefined') {
        if (!photo.startsWith('http') && !photo.startsWith('assets')) {
          return '${ApiService.baseUrl}${photo.startsWith('/') ? '' : '/'}$photo';
        }
        return photo;
      }

      if (userData!['photos'] is List && (userData!['photos'] as List).isNotEmpty) {
        final firstP = (userData!['photos'] as List).first;
        final pUrl = (firstP is Map) ? (firstP['url'] ?? firstP['filePath']) : firstP?.toString();
        if (pUrl != null && pUrl.toString().trim().isNotEmpty && pUrl.toString() != 'null') {
          final s = pUrl.toString();
          return s.startsWith('http') || s.startsWith('assets') ? s : '${ApiService.baseUrl}${s.startsWith('/') ? '' : '/'}$s';
        }
      }
    }
    return null;
  }

  String get _effectiveTier {
    if (overrideTier != null) return overrideTier!.toUpperCase();
    final resolved = _resolvedUser;
    if (resolved != null) return resolved.subscriptionTier.toUpperCase();
    if (userData != null) {
      final t = userData!['subscriptionTier']?.toString().toUpperCase();
      if (t != null && t.isNotEmpty) return t;
    }
    return 'FREE';
  }

  Gradient _tierGradient(String tier) {
    switch (tier) {
      case 'ELITE':
        return const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFB703), Color(0xFFFFD700), Color(0xFFFFC107)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'PRO':
        return const LinearGradient(
          colors: [Color(0xFFE100FF), Color(0xFF7F00FF), Color(0xFFE100FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'PLUS':
        return const LinearGradient(
          colors: [Color(0xFF7F00FF), Color(0xFFAA44FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'CORE':
        return const LinearGradient(
          colors: [Color(0xFF00A9FF), Color(0xFF0066FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return LunaraTheme.primaryGradient;
    }
  }

  @override
  Widget build(BuildContext context) {
    String? photo = _profilePhoto;

    if (photo != null &&
        photo.isNotEmpty &&
        photo.startsWith('/') &&
        !photo.startsWith('assets')) {
      photo = '${ApiService.baseUrl}$photo';
    }

    final bool isNetwork =
        photo != null && photo.isNotEmpty && photo.startsWith('http');

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[100],
      backgroundImage: isNetwork
          ? CachedNetworkImageProvider(photo) as ImageProvider
          : AssetImage(
              (photo != null && photo.isNotEmpty)
                  ? photo
                  : LunaraTheme.defaultAvatar,
            ),
    );


    if (showGradientBorder) {
      final String tier = _effectiveTier;
      final Gradient gradient = _tierGradient(tier);

      // Double-width ring for PRO and ELITE tiers for extra prominence
      final double ringWidth = (tier == 'PRO' || tier == 'ELITE') ? (borderWidth + 1.0) : borderWidth;

      avatar = Stack(
        children: [
          Container(
            padding: EdgeInsets.all(ringWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: avatar,
            ),
          ),
          // Tier badge for PRO and ELITE
          if (tier == 'ELITE' || tier == 'PRO')
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: (radius * 0.6).clamp(12.0, 20.0),
                height: (radius * 0.6).clamp(12.0, 20.0),
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: tier == 'ELITE'
                          ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                          : const Color(0xFFE100FF).withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    tier == 'ELITE' ? Icons.star_rounded : Icons.verified_rounded,
                    color: Colors.white,
                    size: (radius * 0.35).clamp(8.0, 14.0),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (isInteractive) {
      return GestureDetector(
        onTap: () {
          final targetUser = _resolvedUser ?? ApiService.cachedCurrentUser;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(user: targetUser),
            ),
          );
        },
        child: avatar,
      );
    }

    return avatar;
  }
}
