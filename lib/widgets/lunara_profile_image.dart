import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../screens/profile/profile_screen.dart';
import '../services/api_service.dart';

class LunaraProfileImage extends StatelessWidget {
  final User? user;
  final Map<String, dynamic>? userData;
  final double radius;
  final bool showGradientBorder;
  final bool isInteractive;
  final double borderWidth;

  const LunaraProfileImage({
    super.key,
    this.user,
    this.userData,
    this.radius = 24,
    this.showGradientBorder = true,
    this.isInteractive = true,
    this.borderWidth = 2,
  });

  User? get _resolvedUser {
    if (user != null) return user;
    if (userData != null) {
      try {
        // Create a temporary User object to leverage its robust path processing
        return User.fromJson(userData!);
      } catch (e) {
        debugPrint('Error resolving user in LunaraProfileImage: $e');
        return null;
      }
    }
    return null;
  }

  String? get _profilePhoto {
    final resolved = _resolvedUser;
    if (resolved != null) return resolved.profilePhoto;
    
    // Fallback logic if resolution fails
    if (userData != null) {
      String? photo = (userData!['profilePhotoUrl'] ?? 
              userData!['profileImageUrl'] ??
              userData!['profilePhoto'] ?? 
              userData!['userAvatar'] ?? 
              userData!['image'] ?? 
              userData!['avatar'])?.toString();
      
      if (photo != null && photo.isNotEmpty && !photo.startsWith('http') && !photo.startsWith('assets')) {
        // Assuming relative path from API
        return '${ApiService.baseUrl}${photo.startsWith('/') ? '' : '/'}$photo';
      }
      return photo;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    String? photo = _profilePhoto;
    
    // Check if it's a relative path that should have been a network image
    if (photo != null && photo.isNotEmpty && photo.startsWith('/') && !photo.startsWith('assets')) {
      photo = '${ApiService.baseUrl}$photo';
    }
    
    final bool isNetwork = photo != null && photo.isNotEmpty && photo.startsWith('http');
    
    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[100],
      backgroundImage: isNetwork 
          ? NetworkImage(photo) as ImageProvider
          : AssetImage((photo != null && photo.isNotEmpty) ? photo : LunaraTheme.defaultAvatar),
    );

    if (showGradientBorder) {
      avatar = Container(
        padding: EdgeInsets.all(borderWidth),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LunaraTheme.primaryGradient,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: avatar,
        ),
      );
    }

    if (isInteractive) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(user: _resolvedUser),
            ),
          );
        },
        child: avatar,
      );
    }

    return avatar;
  }
}
