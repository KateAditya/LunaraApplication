import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import 'profile_details_screen.dart';
import '../../services/api_service.dart';

class ProfilePhotosScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfilePhotosScreen({super.key, this.collectedData});

  @override
  State<ProfilePhotosScreen> createState() => _ProfilePhotosScreenState();
}

class _ProfilePhotosScreenState extends State<ProfilePhotosScreen> {
  // Slot 0 = selfie/primary verification, slots 1–5 = gallery
  final List<String?> _photos = List.generate(6, (index) => null);
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  bool _selfieVerified = false; // true when face detected in slot 0

  Future<void> _pickImage(int index, ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image == null) return;

      setState(() => _isProcessing = true);

      // Run face detection — mandatory for selfie slot (index 0)
      try {
        final inputImage = InputImage.fromFilePath(image.path);
        final faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: false,
            enableClassification: false,
          ),
        );

        final List<Face> faces = await faceDetector.processImage(inputImage);
        await faceDetector.close();

        setState(() {
          _isProcessing = false;
          _photos[index] = image.path;
          if (index == 0) {
            _selfieVerified = faces.isNotEmpty;
          }
        });

        if (index == 0 && faces.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ No face detected. Use a clear selfie for verification.',
              ),
              backgroundColor: LunaraTheme.primaryDeep,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _photos[index] = image.path;
          if (index == 0) _selfieVerified = false;
        });
        debugPrint('Face detection error: $e, accepting photo anyway.');
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: LunaraTheme.primaryDeep,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog(int index) {
    final isSelfieSlot = index == 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSelfieSlot ? 'SELFIE VERIFICATION' : 'ADD PHOTO',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (isSelfieSlot)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    'Take a clear selfie so we can verify your identity.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.54),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: LunaraTheme.accentVivid,
                ),
                title: Text(
                  isSelfieSlot ? 'Take a Selfie' : 'Take a Photo',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(index, ImageSource.camera);
                },
              ),
              if (!isSelfieSlot)
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: LunaraTheme.accentVivid,
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(index, ImageSource.gallery);
                  },
                ),
              if (isSelfieSlot)
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: LunaraTheme.accentVivid,
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Must be a clear face photo',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(index, ImageSource.gallery);
                  },
                ),
              if (_photos[index] != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: LunaraTheme.primaryDeep,
                  ),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(color: LunaraTheme.primaryDeep),
                  ),
                  onTap: () {
                    setState(() {
                      _photos[index] = null;
                      if (index == 0) _selfieVerified = false;
                    });
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  int get _photoCount => _photos.whereType<String>().length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                _buildProgressBar(),
                const SizedBox(height: 32),
                Text(
                  'STEP 1 / 4',
                  style: LunaraTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: LunaraTheme.accentVivid,
                  ),
                ),
                Text(
                  'ADD PHOTOS',
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 32,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'First slot = selfie for verification. Add at least 1 photo.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.54),
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                // Selfie verification status chip
                _buildVerificationBadge(),
                const SizedBox(height: 20),
                Expanded(
                  child: Stack(
                    children: [
                      GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                        itemCount: 6,
                        itemBuilder: (context, index) {
                          return _buildPhotoSlot(index);
                        },
                      ),
                      if (_isProcessing)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: LunaraTheme.accentVivid,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Detecting face...',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                LunaraActionButton(
                  text: 'CONTINUE',
                  onPressed: _photoCount >= 2
                      ? () async {
                          if (_photos[0] == null || _photos[1] == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please upload both a selfie (Slot 1) and a profile photo (Slot 2)',
                                ),
                              ),
                            );
                            return;
                          }

                          setState(() => _isProcessing = true);
                          final selfieBytes = await File(
                            _photos[0]!,
                          ).readAsBytes();
                          final profileBytes = await File(
                            _photos[1]!,
                          ).readAsBytes();
                          final result = await ApiService.verifyFace(
                            profileBytes,
                            selfieBytes,
                          );
                          setState(() => _isProcessing = false);

                          if (result == null || result['success'] != true) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result?['message'] ??
                                        'Face verification failed. Please try again.',
                                  ),
                                  backgroundColor: LunaraTheme.primaryDeep,
                                ),
                              );
                            }
                            return;
                          }

                          final data = widget.collectedData != null
                              ? Map<String, dynamic>.from(widget.collectedData!)
                              : <String, dynamic>{};

                          data['photos'] = _photos.whereType<String>().toList();
                          data['selfieVerified'] = true; // Verified by backend

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ProfileDetailsScreen(collectedData: data),
                            ),
                          );
                        }
                      : null,
                ),
                if (_photoCount < 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: Text(
                        'Add a selfie (slot 1) and profile photo (slot 2) to continue',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.38),
                          fontSize: 12,
                        ),
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

  Widget _buildVerificationBadge() {
    if (_photos[0] == null) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.05),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.face_outlined,
                  size: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.38),
                ),
                const SizedBox(width: 6),
                Text(
                  'SELFIE NOT UPLOADED',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _selfieVerified
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                  : LunaraTheme.primaryDeep.withValues(alpha: 0.5),
            ),
            color: _selfieVerified
                ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                : LunaraTheme.primaryDeep.withValues(alpha: 0.1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _selfieVerified
                    ? Icons.verified_user
                    : Icons.warning_amber_rounded,
                size: 14,
                color: _selfieVerified
                    ? const Color(0xFF4CAF50)
                    : LunaraTheme.primaryDeep,
              ),
              const SizedBox(width: 6),
              Text(
                _selfieVerified ? 'SELFIE VERIFIED ✓' : 'FACE NOT DETECTED',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: _selfieVerified
                      ? const Color(0xFF4CAF50)
                      : LunaraTheme.primaryDeep,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        TextButton(
          onPressed: () {
            // Skip — navigate without photos
            final data = widget.collectedData != null
                ? Map<String, dynamic>.from(widget.collectedData!)
                : <String, dynamic>{};
            data['photos'] = <String>[];
            data['selfieVerified'] = false;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileDetailsScreen(collectedData: data),
              ),
            );
          },
          child: Text(
            'SKIP',
            style: LunaraTheme.bodyStyle.copyWith(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.38),
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: List.generate(4, (index) {
        final active = index == 0;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 4,
            decoration: BoxDecoration(
              color: active
                  ? LunaraTheme.accentVivid
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: LunaraTheme.accentVivid.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPhotoSlot(int index) {
    final photo = _photos[index];
    final isSelfieSlot = index == 0;

    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      borderColor: isSelfieSlot
          ? (_selfieVerified
                ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                : LunaraTheme.accentVivid.withValues(alpha: 0.5))
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: (kIsWeb || photo.startsWith('http'))
                  ? Image.network(photo, fit: BoxFit.cover)
                  : Image.file(File(photo), fit: BoxFit.cover),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelfieSlot
                        ? Icons.face_retouching_natural
                        : Icons.add_a_photo_outlined,
                    color: isSelfieSlot
                        ? LunaraTheme.accentVivid
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.24),
                    size: 26,
                  ),
                  if (isSelfieSlot) ...[
                    const SizedBox(height: 6),
                    Text(
                      'SELFIE',
                      style: TextStyle(
                        color: LunaraTheme.accentVivid,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Top badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelfieSlot
                    ? (_selfieVerified
                          ? const Color(0xFF4CAF50)
                          : LunaraTheme.accentVivid)
                    : Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isSelfieSlot
                    ? (_selfieVerified ? '✓ ID' : 'SELFIE')
                    : '${index + 1}',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Tap target
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showImageSourceDialog(index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
