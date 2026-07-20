import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/top_error_banner.dart';
import '../../services/api_service.dart';
import '../../services/onboarding_service.dart';
import 'profile_photos_screen.dart';

class SelfieVerificationScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const SelfieVerificationScreen({super.key, this.collectedData});

  @override
  State<SelfieVerificationScreen> createState() => _SelfieVerificationScreenState();
}

class _SelfieVerificationScreenState extends State<SelfieVerificationScreen> {
  int _currentStep = 1; // 1 = Upload Reference Photo, 2 = Live Front Selfie Check
  String? _referencePhotoPath; // Uploaded clear face photo
  String? _liveSelfiePath; // Captured live front camera selfie
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Restore saved progress if available
    if (widget.collectedData != null) {
      if (widget.collectedData!['referencePhoto'] != null) {
        _referencePhotoPath = widget.collectedData!['referencePhoto'];
        _currentStep = 2;
      }
      if (widget.collectedData!['selfie'] != null) {
        _liveSelfiePath = widget.collectedData!['selfie'];
      }
    }
  }

  /// Step 1: Pick Reference Face Photo (Gallery or Camera)
  Future<void> _pickReferencePhoto(ImageSource source) async {
    try {
      // Auto-compress reference face photo to ~150 KB
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 700,
        maxHeight: 700,
        imageQuality: 55,
      );

      if (photo == null) return;

      setState(() => _isProcessing = true);

      // Verify that the reference photo contains a readable human face (blocks bottles, cars, objects)
      final res = await ApiService.detectFace(photo.path);

      setState(() => _isProcessing = false);

      if (!mounted) return;

      if (res['hasFace'] == true) {
        setState(() {
          _referencePhotoPath = photo.path;
          _currentStep = 2; // Advance to live selfie camera step
        });

        final data = widget.collectedData != null
            ? Map<String, dynamic>.from(widget.collectedData!)
            : <String, dynamic>{};
        data['referencePhoto'] = photo.path;
        await OnboardingService.saveProgress('selfie_verification', data);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Human face detected! Now take a live selfie with your front camera.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
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
              res['message'] ?? 'Could not detect a human face. Please upload a clear photo showing your face (photos of bottles, objects, or scenery are not allowed).',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('RETRY PHOTO', style: TextStyle(color: LunaraTheme.primaryRich, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        TopErrorBanner.show(context, 'Failed to pick photo: $e');
      }
    }
  }

  /// Step 2: Capture Live Selfie strictly using Front Camera ONLY (No Gallery Upload Allowed)
  Future<void> _captureLiveSelfie() async {
    try {
      // Force front camera and auto-compress live selfie to ~150 KB
      final XFile? selfie = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 700,
        maxHeight: 700,
        imageQuality: 55,
      );

      if (selfie == null) return;

      setState(() {
        _liveSelfiePath = selfie.path;
      });

      final data = widget.collectedData != null
          ? Map<String, dynamic>.from(widget.collectedData!)
          : <String, dynamic>{};
      data['referencePhoto'] = _referencePhotoPath;
      data['selfie'] = selfie.path;
      await OnboardingService.saveProgress('selfie_verification', data);
    } catch (e) {
      if (mounted) {
        TopErrorBanner.show(context, 'Failed to capture live selfie: $e');
      }
    }
  }

  /// Verify 1:1 Identity Match between Uploaded Reference Photo and Live Front Selfie
  Future<void> _handleFinalFaceMatch() async {
    if (_referencePhotoPath == null) {
      TopErrorBanner.show(context, 'Please upload a reference face photo first');
      return;
    }
    if (_liveSelfiePath == null) {
      TopErrorBanner.show(context, 'Please capture a live front camera selfie');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final res = await ApiService.verifyFace(
        selfiePath: _liveSelfiePath!,
        profilePhotoPath: _referencePhotoPath!,
      );

      setState(() => _isProcessing = false);

      if (!mounted) return;

      if (res['verified'] == true || res['success'] == true) {
        final double confidencePct = ((res['confidence'] as double? ?? 0.95) * 100);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Theme.of(context).cardColor,
            title: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('Face Verified!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Azure AI Face Service matched your live selfie with your reference photo!',
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Match Confidence: ${confidencePct.toStringAsFixed(1)}%\n1:1 Face Identity Verified ✓',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);

                  final data = widget.collectedData != null
                      ? Map<String, dynamic>.from(widget.collectedData!)
                      : <String, dynamic>{};

                  data['referencePhoto'] = _referencePhotoPath;
                  data['selfie'] = _liveSelfiePath;
                  data['isFaceVerified'] = true;
                  data['faceMatchConfidence'] = res['confidence'];

                  // Advance to profile photos upload step
                  await OnboardingService.saveProgress('profile_photos', data);

                  if (!mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePhotosScreen(collectedData: data),
                    ),
                  );
                },
                child: const Text(
                  'CONTINUE TO PROFILE PHOTOS',
                  style: TextStyle(
                    color: LunaraTheme.primaryRich,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Theme.of(context).cardColor,
            title: const Row(
              children: [
                Icon(Icons.face_unlock_outlined, color: Colors.redAccent, size: 28),
                SizedBox(width: 10),
                Text('Face Match Failed', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              res['message'] ?? 'Your live selfie did not match the uploaded reference photo. Please retake the selfie under good lighting.',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('RETRY LIVE SELFIE', style: TextStyle(color: LunaraTheme.primaryRich, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        TopErrorBanner.show(context, 'Verification error: $e');
      }
    }
  }

  void _showReferencePhotoPickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: LunaraTheme.primaryRich),
              title: const Text('Choose Clear Photo from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickReferencePhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: LunaraTheme.primaryRich),
              title: const Text('Take Clear Photo with Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickReferencePhoto(ImageSource.camera);
              },
            ),
          ],
        ),
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
              _buildStepIndicator(),
              const SizedBox(height: 12),
              Text(
                _currentStep == 1
                    ? '1. UPLOAD FACE PHOTO'
                    : '2. LIVE FRONT SELFIE CHECK',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentStep == 1
                    ? 'Upload a clear, well-lit photo of your face so Azure AI can register your biometric profile.'
                    : 'Now open your front camera for a live selfie match. Gallery uploads are disabled for this step.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              if (_currentStep == 1) _buildStep1UI() else _buildStep2UI(),
              const SizedBox(height: 32),
              if (_isProcessing)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: LunaraTheme.primaryRich),
                      SizedBox(height: 14),
                      Text(
                        'Analyzing face with Azure AI...',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else if (_currentStep == 2)
                LunaraActionButton(
                  text: 'VERIFY MATCH WITH AZURE AI',
                  onPressed: _liveSelfiePath != null ? _handleFinalFaceMatch : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: LunaraTheme.primaryRich.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LunaraTheme.primaryRich.withValues(alpha: 0.3)),
      ),
      child: Text(
        'FACE VERIFICATION STEP $_currentStep / 2',
        style: const TextStyle(
          color: LunaraTheme.primaryRich,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
      onPressed: () {
        if (_currentStep == 2 && _referencePhotoPath != null) {
          setState(() => _currentStep = 1);
        } else {
          Navigator.pop(context);
        }
      },
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
        _progressSegment(completed: false, active: true, label: 'SELFIE'),
        const SizedBox(width: 6),
        _progressSegment(completed: false, active: false, label: 'PHOTOS'),
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

  Widget _buildImageWidget(String path) {
    if (kIsWeb || path.startsWith('http') || path.startsWith('blob:')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  /// UI for Step 1: Upload Reference Face Photo
  Widget _buildStep1UI() {
    final bool hasRef = _referencePhotoPath != null;

    return Center(
      child: GestureDetector(
        onTap: _showReferencePhotoPickerModal,
        child: Container(
          width: 240,
          height: 280,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasRef ? Colors.green : LunaraTheme.primaryRich,
              width: 2,
            ),
            boxShadow: LunaraTheme.premiumShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: hasRef
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImageWidget(_referencePhotoPath!),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('CLEAR FACE ✓', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: LunaraTheme.primaryRich.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 44,
                          color: LunaraTheme.primaryRich,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'UPLOAD CLEAR FACE PHOTO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: LunaraTheme.primaryRich,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gallery or Camera',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// UI for Step 2: Live Front Camera Selfie
  Widget _buildStep2UI() {
    return Column(
      children: [
        Row(
          children: [
            // Left Card: Uploaded Reference Photo
            Expanded(
              child: Column(
                children: [
                  const Text('1. Reference Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    height: 170,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _buildImageWidget(_referencePhotoPath!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Right Card: Live Front Camera Selfie (Camera ONLY, No gallery allowed)
            Expanded(
              child: Column(
                children: [
                  const Text('2. Live Front Selfie', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _captureLiveSelfie, // Directly triggers front camera
                    child: Container(
                      height: 170,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _liveSelfiePath != null ? LunaraTheme.primaryRich : Colors.orange,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _liveSelfiePath != null
                            ? _buildImageWidget(_liveSelfiePath!)
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.camera_front, size: 36, color: LunaraTheme.primaryRich),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'OPEN FRONT CAMERA',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: LunaraTheme.primaryRich,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Camera only (No upload)',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
