import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import 'profile_details_screen.dart';

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

      final sizeInBytes = await image.length();
      if (sizeInBytes > 500 * 1024) {
        setState(() => _isProcessing = false);
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Theme.of(context).cardColor,
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'File Too Large',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Text(
                'The selected photo is ${(sizeInBytes / 1024).toStringAsFixed(1)} KB. Please choose an image smaller than 500 KB.',
                style: const TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: LunaraTheme.accentVivid,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      setState(() {
        _isProcessing = false;
        _photos[index] = image.path;
      });
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: LunaraTheme.accentVivid.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LunaraTheme.accentVivid.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: LunaraTheme.accentVivid,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Note: Profile pictures and gallery photos must be less than 500 KB.',
                          style: TextStyle(
                            color: LunaraTheme.accentVivid,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

                          final data = widget.collectedData != null
                              ? Map<String, dynamic>.from(widget.collectedData!)
                              : <String, dynamic>{};

                          data['photos'] = _photos.whereType<String>().toList();

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
          ? LunaraTheme.accentVivid.withValues(alpha: 0.5)
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
                    ? LunaraTheme.accentVivid
                    : Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isSelfieSlot
                    ? 'SELFIE'
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
