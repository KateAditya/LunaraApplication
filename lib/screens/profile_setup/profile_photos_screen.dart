import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import '../../widgets/top_error_banner.dart';
import '../../services/onboarding_service.dart';
import '../../services/api_service.dart';
import 'profile_details_screen.dart';

class ProfilePhotosScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfilePhotosScreen({super.key, this.collectedData});

  @override
  State<ProfilePhotosScreen> createState() => _ProfilePhotosScreenState();
}

class _ProfilePhotosScreenState extends State<ProfilePhotosScreen> {
  // Slot 0 = Verified Selfie, Slots 1–5 = Profile Pictures
  final List<String?> _photos = List.generate(6, (index) => null);
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Restore saved profile photos if available
    if (widget.collectedData != null && widget.collectedData!['photos'] != null) {
      final savedPhotos = List<String>.from(widget.collectedData!['photos']);
      for (int i = 0; i < savedPhotos.length && i < 6; i++) {
        _photos[i] = savedPhotos[i];
      }
    }
  }

  Future<void> _pickImage(int index, ImageSource source) async {
    try {
      // Auto-compress photo to ~150 KB with 700x700 resolution and 55% quality
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 700,
        maxHeight: 700,
        imageQuality: 55,
      );
      if (image == null) return;

      setState(() => _isProcessing = true);

      // Validate that the photo contains a human face (blocks bottles, cars, objects)
      final faceCheck = await ApiService.detectFace(image.path);

      setState(() => _isProcessing = false);

      if (!mounted) return;

      if (faceCheck['hasFace'] != true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Theme.of(context).cardColor,
            title: const Row(
              children: [
                Icon(Icons.no_accounts_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 10),
                Text('No Face Detected', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              faceCheck['message'] ?? 'No human face detected in this photo. Please upload a clear photo of yourself (photos of bottles, objects, or scenery are not allowed).',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CHOOSE ANOTHER PHOTO', style: TextStyle(color: LunaraTheme.primaryRich, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }

      setState(() {
        _photos[index] = image.path;
      });

      // Save onboarding progress
      final data = widget.collectedData != null
          ? Map<String, dynamic>.from(widget.collectedData!)
          : <String, dynamic>{};
      data['photos'] = _photos.whereType<String>().toList();
      await OnboardingService.saveProgress('profile_photos', data);

    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        TopErrorBanner.show(context, 'Error picking image: $e');
      }
    }
  }

  void _showImageSourceDialog(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: LunaraTheme.primaryRich),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(index, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: LunaraTheme.primaryRich),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(index, ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleContinue() async {
    final validPhotos = _photos.whereType<String>().toList();
    if (validPhotos.isEmpty) {
      TopErrorBanner.show(context, 'Please upload at least 1 profile picture (Main Photo)');
      return;
    }

    final data = widget.collectedData != null
        ? Map<String, dynamic>.from(widget.collectedData!)
        : <String, dynamic>{};

    data['photos'] = validPhotos;

    // Save progress to next step
    await OnboardingService.saveProgress('profile_details', data);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileDetailsScreen(collectedData: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildProgressBar(),
              const SizedBox(height: 24),
              _buildVerifiedBadge(),
              const SizedBox(height: 16),
              Text(
                'YOUR PROFILE',
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ADD PROFILE PHOTOS',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 28,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload at least 1 public profile photo. People with clear profile photos get 5x more matches!',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              _buildPhotoGrid(),
              const SizedBox(height: 40),
              _isProcessing
                  ? const Center(
                      child: CircularProgressIndicator(color: LunaraTheme.primaryRich),
                    )
                  : LunaraActionButton(
                      text: 'CONTINUE TO DETAILS',
                      onPressed: _handleContinue,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text(
              'Azure AI Face Verification Completed ✓',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
      onPressed: () => Navigator.pop(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: [
        _progressSegment(completed: true, active: true, label: 'INFO'),
        const SizedBox(width: 6),
        _progressSegment(completed: true, active: true, label: 'VERIFY'),
        const SizedBox(width: 6),
        _progressSegment(completed: true, active: true, label: 'SELFIE'),
        const SizedBox(width: 6),
        _progressSegment(completed: false, active: true, label: 'PHOTOS'),
        const SizedBox(width: 6),
        _progressSegment(completed: false, active: false, label: 'DETAILS'),
      ],
    );
  }

  Widget _progressSegment({
    required bool active,
    required bool completed,
    required String label,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: completed || active
                  ? LunaraTheme.primaryRich
                  : LunaraTheme.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return Column(
      children: [
        // Primary Slot 0 (Main Profile Photo) & Slot 1
        Row(
          children: [
            Expanded(child: _buildPhotoTile(0, isMain: true)),
            const SizedBox(width: 16),
            Expanded(child: _buildPhotoTile(1)),
          ],
        ),
        const SizedBox(width: 16, height: 16),
        // Secondary Slots 2, 3, 4, 5
        Row(
          children: [
            Expanded(child: _buildPhotoTile(2)),
            const SizedBox(width: 12),
            Expanded(child: _buildPhotoTile(3)),
            const SizedBox(width: 12),
            Expanded(child: _buildPhotoTile(4)),
            const SizedBox(width: 12),
            Expanded(child: _buildPhotoTile(5)),
          ],
        ),
      ],
    );
  }

  Widget _buildImageWidget(String path) {
    if (kIsWeb || path.startsWith('http') || path.startsWith('blob:')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  Widget _buildPhotoTile(int index, {bool isMain = false}) {
    final photoPath = _photos[index];
    final hasPhoto = photoPath != null;

    return AspectRatio(
      aspectRatio: 0.85,
      child: GestureDetector(
        onTap: () => _showImageSourceDialog(index),
        child: GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isMain
                    ? LunaraTheme.primaryRich
                    : LunaraTheme.lightBorder,
                width: isMain ? 2 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasPhoto)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: _buildImageWidget(photoPath),
                  )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        color: LunaraTheme.primaryRich.withValues(alpha: 0.6),
                        size: isMain ? 28 : 20,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isMain ? 'MAIN PHOTO' : 'ADD PHOTO',
                        style: TextStyle(
                          fontSize: isMain ? 11 : 9,
                          fontWeight: FontWeight.bold,
                          color: LunaraTheme.primaryRich,
                        ),
                      ),
                    ],
                  ),
                if (isMain && hasPhoto)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: LunaraTheme.primaryRich,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'MAIN PHOTO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (hasPhoto)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () async {
                        setState(() => _photos[index] = null);
                        final data = widget.collectedData != null
                            ? Map<String, dynamic>.from(widget.collectedData!)
                            : <String, dynamic>{};
                        data['photos'] = _photos.whereType<String>().toList();
                        await OnboardingService.saveProgress('profile_photos', data);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
