import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/subscription_provider.dart';
import '../../widgets/subscription_limit_dialog.dart';

class EditProfileScreen extends StatefulWidget {
  final User user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  late TextEditingController _genderController;
  late TextEditingController _cityController;
  late TextEditingController _bioController;
  late TextEditingController _lookingForController;
  late TextEditingController _musicController;
  late TextEditingController _smokingController;
  late TextEditingController _drinkController;
  late TextEditingController _occupationController;
  late TextEditingController _educationController;
  late TextEditingController _minBudgetController;
  late TextEditingController _maxBudgetController;
  late TextEditingController _prefGendersController;
  late TextEditingController _minAgeController;
  late TextEditingController _maxAgeController;
  late TextEditingController _matchDistanceController;

  bool _invisibleMode = false;
  bool _bookingAlerts = true;

  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _localProfilePhotoBytes;
  bool _photoDeleted = false;
  List<Map<String, String>> _localPhotoDetails = [];
  String? _currentProfilePhotoUrl;

  void _showMinPhotosRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: LunaraTheme.electricViolet, size: 28),
            SizedBox(width: 10),
            Text(
              'Minimum 3 Photos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'A minimum of 3 profile pictures is required for your profile. Please upload a new photo before deleting this one.',
          style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: LunaraTheme.electricViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('GOT IT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePhoto() async {
    String? photoId;
    if (_localPhotoDetails.isNotEmpty) {
      final primary = _localPhotoDetails.firstWhere(
        (p) => p['isPrimary'] == 'true' || p['url'] == _currentProfilePhotoUrl,
        orElse: () => _localPhotoDetails.first,
      );
      photoId = primary['id'];
    }
    await _deletePhotoById(photoId);
  }

  Future<void> _showImageSourceBottomSheet({bool isMainProfilePhoto = true}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select Photo Source',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: LunaraTheme.electricViolet),
                  title: Text(
                    'Take Photo',
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadPhotoFromSource(ImageSource.camera, isMainProfilePhoto: isMainProfilePhoto);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: LunaraTheme.electricViolet),
                  title: Text(
                    isMainProfilePhoto ? 'Choose from Gallery' : 'Choose from Gallery (Multiple)',
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadPhotoFromSource(ImageSource.gallery, isMainProfilePhoto: isMainProfilePhoto);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadPhoto({bool isMainProfilePhoto = true}) async {
    await _showImageSourceBottomSheet(isMainProfilePhoto: isMainProfilePhoto);
  }

  Future<void> _pickAndUploadPhotoFromSource(ImageSource source, {required bool isMainProfilePhoto}) async {
    try {
      List<XFile> images = [];
      if (isMainProfilePhoto) {
        final XFile? image = await _picker.pickImage(
          source: source,
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 95,
        );
        if (image != null) images.add(image);
      } else {
        if (source == ImageSource.camera) {
          final XFile? image = await _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 95,
          );
          if (image != null) images.add(image);
        } else {
          images = await _picker.pickMultiImage(
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 95,
          );
        }
      }

      if (images.isEmpty) return;

      setState(() => _isLoading = true);

      final List<Uint8List> bytesList = [];
      final List<String> namesList = [];
      for (var image in images) {
        final bytes = await image.readAsBytes();
        bytesList.add(bytes);
        namesList.add(image.name);
      }
      
      final success = await ApiService.uploadProfilePhotos(
        bytesList,
        namesList,
        isPrimary: isMainProfilePhoto,
      );
      
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (success && isMainProfilePhoto) {
          _localProfilePhotoBytes = bytesList.first;
          _photoDeleted = false;
        }
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        await _refreshProfileData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photos uploaded successfully!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photos.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _refreshProfileData() async {
    final updatedUser = await ApiService.fetchProfile(userId: widget.user.id, forceRefresh: true);
    if (updatedUser != null && mounted) {
       setState(() {
         _localPhotoDetails = List.from(updatedUser.photoDetails);
         _currentProfilePhotoUrl = updatedUser.profilePhoto;
         _localProfilePhotoBytes = null;
         _photoDeleted = false;
       });
       ApiService.profileUpdateNotifier.value++;
    }
  }

  Future<void> _deletePhotoById(String? photoId) async {
    if (_localPhotoDetails.length <= 3) {
      _showMinPhotosRequiredDialog();
      return;
    }

    if (photoId == null || photoId.isEmpty) {
       if (_localProfilePhotoBytes != null) {
         setState(() {
           _localProfilePhotoBytes = null;
           _photoDeleted = true;
         });
         return;
       }
       ScaffoldMessenger.of(context).hideCurrentSnackBar();
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Cannot delete photo. Please refresh your profile.'), backgroundColor: Colors.orange),
       );
       return;
    }

    setState(() => _isLoading = true);
    final result = await ApiService.deleteProfilePhoto(photoId);
    final bool success = result['success'] == true;
    final String message = result['message']?.toString() ?? (success ? 'Photo deleted successfully!' : 'Failed to delete photo.');
    
    if (!mounted) return;
    
    if (success) {
       await _refreshProfileData();
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(message), backgroundColor: Colors.green),
       );
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(message), backgroundColor: Colors.red),
       );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _setAsPrimaryPhoto(String photoId) async {
    if (photoId.isEmpty) return;

    setState(() => _isLoading = true);
    final result = await ApiService.setPrimaryPhoto(photoId);
    final bool success = result['success'] == true;
    final String message = result['message']?.toString() ?? (success ? 'Profile picture updated successfully!' : 'Failed to update profile picture.');
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (success) {
      await _refreshProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showPhotoOptionsModal(Map<String, String> photo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPrimary = photo['isPrimary'] == 'true' || photo['url'] == _currentProfilePhotoUrl;
    final photoId = photo['id'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Photo Options',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                if (!isPrimary)
                  ListTile(
                    leading: const Icon(Icons.star_rounded, color: LunaraTheme.electricViolet, size: 26),
                    title: Text(
                      'Set as Profile Picture',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setAsPrimaryPhoto(photoId);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
                  title: const Text(
                    'Delete Photo',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deletePhotoById(photoId);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54, size: 24),
                  title: Text(
                    'Cancel',
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Registration-style Chip Option Lists ─────────────────────────────
  final List<String> _interestsOptions = [
    'TRAVEL', 'FITNESS', 'MOVIES', 'MUSIC', 'FOOD', 'PHOTOGRAPHY',
    'GAMING', 'BUSINESS', 'STARTUPS', 'ENTREPRENEURSHIP', 'SPORTS',
    'READING', 'DANCING', 'ART', 'FASHION', 'PETS', 'NATURE', 'ADVENTURE',
  ];
  late Set<String> _selectedInterests;

  final List<String> _lookingForOptions = [
    'NEW FRIENDS', 'SOCIAL OUTINGS', 'ACTIVITY PARTNER', 'NETWORKING',
    'EVENT COMPANIONS', 'CASUAL MEETUPS', 'MEANINGFUL CONNECTIONS',
  ];
  late Set<String> _selectedLookingFor;

  final List<String> _musicOptions = [
    'BOLLYWOOD', 'PUNJABI', 'EDM / TECHNO', 'HIP HOP', 'COMMERCIAL', 'ROCK', 'POP', 'INDIE',
  ];
  late Set<String> _selectedMusic;

  final List<String> _smokingOptions = [
    'NON-SMOKER', 'OCCASIONAL', 'REGULAR', 'NOT FOR ME',
  ];
  String? _selectedSmoking;

  final List<String> _drinkOptions = [
    'NON-DRINKER', 'SOCIALLY', 'REGULAR', 'TEETOTALER',
  ];
  late Set<String> _selectedDrink;

  final List<String> _genderPrefOptions = [
    'MALE', 'FEMALE', 'ALL',
  ];
  late Set<String> _selectedPrefGenders;

  final List<Map<String, dynamic>> _distanceOptions = [
    {'label': '5 KM', 'value': 5},
    {'label': '10 KM', 'value': 10},
    {'label': '25 KM', 'value': 25},
    {'label': '50 KM', 'value': 50},
    {'label': '100 KM+', 'value': 100},
  ];
  int _selectedDistance = 10;

  @override
  void initState() {
    super.initState();
    _currentProfilePhotoUrl = widget.user.profilePhoto;
    _localPhotoDetails = List.from(widget.user.photoDetails);
    final u = widget.user;
    _firstNameController = TextEditingController(text: u.firstName);
    _lastNameController = TextEditingController(text: u.lastName);
    _phoneController = TextEditingController(text: u.phone);
    _dobController = TextEditingController(text: u.dateOfBirth ?? '');
    _genderController = TextEditingController(text: u.gender ?? '');
    _cityController = TextEditingController(text: u.city ?? '');
    _bioController = TextEditingController(text: u.bio ?? '');
    _lookingForController = TextEditingController(text: u.lookingFor.join(', '));
    _musicController = TextEditingController(text: u.musicPreference.join(', '));
    _smokingController = TextEditingController(text: u.smokingPreference ?? '');
    _drinkController = TextEditingController(text: u.drinkPreference.join(', '));
    _occupationController = TextEditingController(text: u.occupation ?? '');
    _educationController = TextEditingController(text: u.education ?? '');
    _minBudgetController = TextEditingController(text: u.minBudget?.toString() ?? '');
    _maxBudgetController = TextEditingController(text: u.maxBudget?.toString() ?? '');
    _prefGendersController = TextEditingController(text: u.preferredGenders.join(', '));
    _minAgeController = TextEditingController(text: u.minAgePreference?.toString() ?? '');
    _maxAgeController = TextEditingController(text: u.maxAgePreference?.toString() ?? '');
    _matchDistanceController = TextEditingController(text: u.matchDistanceKm?.toString() ?? '10');
    _invisibleMode = u.invisibleMode;
    _bookingAlerts = u.bookingAlertsEnabled;

    // Initialize Chip Sets
    _selectedInterests = u.interests.map((e) => e.toUpperCase()).toSet();
    for (final item in _selectedInterests) {
      if (!_interestsOptions.contains(item)) _interestsOptions.add(item);
    }

    _selectedLookingFor = u.lookingFor.map((e) => e.toUpperCase()).toSet();
    for (final item in _selectedLookingFor) {
      if (!_lookingForOptions.contains(item)) _lookingForOptions.add(item);
    }

    _selectedMusic = u.musicPreference.map((e) => e.toUpperCase()).toSet();
    for (final item in _selectedMusic) {
      if (!_musicOptions.contains(item)) _musicOptions.add(item);
    }

    _selectedSmoking = u.smokingPreference?.toUpperCase();
    if (_selectedSmoking != null && _selectedSmoking!.isNotEmpty && !_smokingOptions.contains(_selectedSmoking)) {
      _smokingOptions.add(_selectedSmoking!);
    }

    _selectedDrink = u.drinkPreference.map((e) => e.toUpperCase()).toSet();
    for (final item in _selectedDrink) {
      if (!_drinkOptions.contains(item)) _drinkOptions.add(item);
    }

    _selectedPrefGenders = u.preferredGenders.map((e) {
      final upper = e.toUpperCase();
      if (upper == 'MEN') return 'MALE';
      if (upper == 'WOMEN') return 'FEMALE';
      if (upper == 'EVERYONE') return 'ALL';
      return upper;
    }).toSet();
    if (_selectedPrefGenders.isEmpty) {
      _selectedPrefGenders.add('ALL');
    }
    for (final item in _selectedPrefGenders) {
      if (!_genderPrefOptions.contains(item)) _genderPrefOptions.add(item);
    }

    _selectedDistance = u.matchDistanceKm ?? 10;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    _lookingForController.dispose();
    _musicController.dispose();
    _smokingController.dispose();
    _drinkController.dispose();
    _occupationController.dispose();
    _educationController.dispose();
    _minBudgetController.dispose();
    _maxBudgetController.dispose();
    _prefGendersController.dispose();
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _matchDistanceController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    final int? minBudget = int.tryParse(_minBudgetController.text.trim());
    final int? maxBudget = int.tryParse(_maxBudgetController.text.trim());
    final int? minAge = int.tryParse(_minAgeController.text.trim());
    final int? maxAge = int.tryParse(_maxAgeController.text.trim());
    
    final Map<String, dynamic> data = {
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'dateOfBirth': _dobController.text.trim(),
      'gender': _genderController.text.trim(),
      'city': _cityController.text.trim(),
      'bio': _bioController.text.trim(),
      'interests': _selectedInterests.toList(),
      'lookingFor': _selectedLookingFor.toList(),
      'musicPreference': _selectedMusic.toList(),
      'smokingPreference': _selectedSmoking ?? '',
      'drinkPreference': _selectedDrink.toList(),
      'occupation': _occupationController.text.trim(),
      'education': _educationController.text.trim(),
      'minBudget': minBudget,
      'maxBudget': maxBudget,
      'preferredGenders': _selectedPrefGenders.toList(),
      'minAgePreference': minAge,
      'maxAgePreference': maxAge,
      'matchDistanceKm': _selectedDistance,
      'invisibleMode': _invisibleMode,
      'showMeInMatching': !_invisibleMode,
      'bookingAlertsEnabled': _bookingAlerts,
    };
    
    data.removeWhere((key, value) => value == null || value == '' || (value is List && value.isEmpty));
    
    final result = await ApiService.updateProfile(data);
    final success = result['success'] == true;
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (success) {
      await ApiService.fetchProfile(userId: widget.user.id, forceRefresh: true);
      if (!mounted) return;
      ApiService.profileUpdateNotifier.value++;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _isLoading = false);
      final msg = result['message'] ?? 'Failed to update profile.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSubLabel(String title, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1.0,
            color: LunaraTheme.electricViolet,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildChipSelector(List<String> options, Set<String> selectedSet) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((option) {
        final isSelected = selectedSet.contains(option);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedSet.remove(option);
              } else {
                selectedSet.add(option);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: isSelected
                  ? LunaraTheme.electricViolet.withValues(alpha: 0.18)
                  : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
              border: Border.all(
                color: isSelected
                    ? LunaraTheme.electricViolet
                    : (isDark ? Colors.white24 : Colors.black12),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(Icons.check_circle, size: 14, color: LunaraTheme.electricViolet),
                  const SizedBox(width: 6),
                ],
                Text(
                  option,
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black54),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSingleChipSelector<T>(List<Map<String, dynamic>> options, T? currentValue, ValueChanged<T> onSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((opt) {
        final label = opt['label'] as String;
        final val = opt['value'] as T;
        final isSelected = currentValue == val;
        return GestureDetector(
          onTap: () {
            setState(() {
              onSelected(val);
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: isSelected
                  ? LunaraTheme.electricViolet.withValues(alpha: 0.18)
                  : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
              border: Border.all(
                color: isSelected
                    ? LunaraTheme.electricViolet
                    : (isDark ? Colors.white24 : Colors.black12),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(Icons.check_circle, size: 14, color: LunaraTheme.electricViolet),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white54 : Colors.black54),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: LunaraTheme.electricViolet,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: controller,
              keyboardType: isNumber ? TextInputType.number : TextInputType.text,
              maxLines: maxLines,
              inputFormatters: inputFormatters,
              validator: validator,
              onTap: () {
                if (controller.text.isNotEmpty &&
                    controller.selection.baseOffset == 0 &&
                    controller.selection.extentOffset == controller.text.length) {
                  controller.selection = TextSelection.collapsed(offset: controller.text.length);
                }
              },
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
                  fontWeight: FontWeight.normal,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderDropdown() {
    final List<String> genders = ['Male', 'Female', 'Other'];
    String currentText = _genderController.text.trim().toLowerCase();
    String? selectedValue;
    if (currentText.startsWith('m')) {
      selectedValue = 'Male';
    } else if (currentText.startsWith('f')) {
      selectedValue = 'Female';
    } else if (currentText.startsWith('o')) {
      selectedValue = 'Other';
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENDER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: LunaraTheme.electricViolet,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DropdownButtonFormField<String>(
              initialValue: selectedValue,
              icon: const Icon(Icons.arrow_drop_down, color: LunaraTheme.electricViolet),
              decoration: InputDecoration(
                hintText: 'Gender',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
                  fontWeight: FontWeight.normal,
                ),
                prefixIcon: Icon(
                  selectedValue == 'Male' ? Icons.male : (selectedValue == 'Female' ? Icons.female : Icons.transgender),
                  color: selectedValue == 'Male' ? Colors.blue : (selectedValue == 'Female' ? Colors.pink : Colors.purple),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
              items: genders.map((String gender) {
                IconData icon;
                Color iconColor;
                if (gender == 'Male') {
                  icon = Icons.male;
                  iconColor = Colors.blue;
                } else if (gender == 'Female') {
                  icon = Icons.female;
                  iconColor = Colors.pink;
                } else {
                  icon = Icons.transgender;
                  iconColor = Colors.purple;
                }

                return DropdownMenuItem<String>(
                  value: gender,
                  child: Row(
                    children: [
                      Icon(icon, color: iconColor, size: 20),
                      const SizedBox(width: 10),
                      Text(gender),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _genderController.text = newValue;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: LunaraTheme.electricViolet,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildHideProfileOption() {
    final hasHideProfile = SubscriptionProvider.instance.hasVipFeature(VipFeature.hideProfile);

    return _buildSwitch('Hide Profile', _invisibleMode, (v) {
      if (!hasHideProfile) {
        showSubscriptionLimitDialog(
          context,
          feature: SubLimitFeature.hideProfile,
        );
        setState(() {}); // Reset switch visually
        return;
      }
      setState(() => _invisibleMode = v);
    });
  }

  Widget _buildSection(String title, List<Widget> children, {bool initiallyExpanded = false}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        tilePadding: EdgeInsets.zero,
        iconColor: LunaraTheme.electricViolet,
        collapsedIconColor: LunaraTheme.electricViolet,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: LunaraTheme.electricViolet),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildOtherPhotosGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _localPhotoDetails.length + 1,
      itemBuilder: (context, index) {
        if (index == _localPhotoDetails.length) {
          return GestureDetector(
            onTap: () => _pickAndUploadPhoto(isMainProfilePhoto: false),
            child: Container(
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.add_a_photo, color: LunaraTheme.electricViolet),
              ),
            ),
          );
        }
        
        final photo = _localPhotoDetails[index];
        final isPrimary = photo['isPrimary'] == 'true' || photo['url'] == _currentProfilePhotoUrl;
        final photoId = photo['id'] ?? '';

        return GestureDetector(
          onTap: () => _showPhotoOptionsModal(photo),
          onLongPress: () => _showPhotoOptionsModal(photo),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: isPrimary
                      ? Border.all(color: LunaraTheme.electricViolet, width: 2.5)
                      : null,
                  image: DecorationImage(
                    image: NetworkImage(photo['url'] ?? ''),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (isPrimary)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: LunaraTheme.electricViolet,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: Colors.white, size: 10),
                        SizedBox(width: 2),
                        Text(
                          'MAIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deletePhotoById(photoId),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EDIT PROFILE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                        backgroundImage: _localProfilePhotoBytes != null
                            ? MemoryImage(_localProfilePhotoBytes!)
                            : (!_photoDeleted && _currentProfilePhotoUrl != null
                                ? NetworkImage(_currentProfilePhotoUrl!)
                                : null) as ImageProvider?,
                        child: _localProfilePhotoBytes == null && (_photoDeleted || _currentProfilePhotoUrl == null)
                            ? const Icon(Icons.person, size: 60, color: LunaraTheme.electricViolet)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndUploadPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: LunaraTheme.electricViolet,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      if (_localProfilePhotoBytes != null || (!_photoDeleted && _currentProfilePhotoUrl != null))
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _deletePhoto,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                _buildSection('PHOTOS', [
                  _buildOtherPhotosGrid(),
                ], initiallyExpanded: true),
                const SizedBox(height: 8),

                _buildSection('BASIC INFO', [
                  _buildTextField(
                    'First Name',
                    _firstNameController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'First name is required';
                      if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val.trim())) {
                        return 'Only upper and lowercase letters allowed';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    'Last Name',
                    _lastNameController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Last name is required';
                      if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val.trim())) {
                        return 'Only upper and lowercase letters allowed';
                      }
                      return null;
                    },
                  ),
                  _buildTextField('Phone', _phoneController),
                  _buildTextField('Date of Birth (YYYY-MM-DD)', _dobController),
                  _buildGenderDropdown(),
                  _buildTextField('City', _cityController),
                  _buildTextField('Bio', _bioController, maxLines: 3),
                ], initiallyExpanded: true),
                const SizedBox(height: 8),
                
                _buildSection('PREFERENCES & LIFESTYLE', [
                  _buildSubLabel('INTERESTS', 'What do you vibe with beyond the night?'),
                  const SizedBox(height: 10),
                  _buildChipSelector(_interestsOptions, _selectedInterests),
                  const SizedBox(height: 20),

                  _buildSubLabel('LOOKING FOR', 'What kind of connections are you seeking?'),
                  const SizedBox(height: 10),
                  _buildChipSelector(_lookingForOptions, _selectedLookingFor),
                  const SizedBox(height: 20),

                  _buildSubLabel('MUSIC PREFERENCE', 'Your favorite party beats'),
                  const SizedBox(height: 10),
                  _buildChipSelector(_musicOptions, _selectedMusic),
                  const SizedBox(height: 20),

                  _buildSubLabel('SMOKING PREFERENCE', 'Smoking habits'),
                  const SizedBox(height: 10),
                  _buildSingleChipSelector<String>(
                    _smokingOptions.map((e) => {'label': e, 'value': e}).toList(),
                    _selectedSmoking,
                    (val) => _selectedSmoking = val,
                  ),
                  const SizedBox(height: 20),

                  _buildSubLabel('DRINK PREFERENCE', 'Drinking habits'),
                  const SizedBox(height: 10),
                  _buildChipSelector(_drinkOptions, _selectedDrink),
                  const SizedBox(height: 12),
                ], initiallyExpanded: true),
                const SizedBox(height: 8),

                _buildSection('WORK & EDUCATION', [
                  _buildTextField('Occupation', _occupationController),
                  _buildTextField('Education', _educationController),
                ], initiallyExpanded: false),
                const SizedBox(height: 8),

                _buildSection('MATCHING & BUDGET', [
                  _buildSubLabel('PREFERRED GENDERS', 'Who would you like to meet?'),
                  const SizedBox(height: 10),
                  _buildChipSelector(_genderPrefOptions, _selectedPrefGenders),
                  const SizedBox(height: 20),

                  _buildSubLabel('MATCH DISTANCE', 'Maximum discovery radius'),
                  const SizedBox(height: 10),
                  _buildSingleChipSelector<int>(
                    _distanceOptions,
                    _selectedDistance,
                    (val) => _selectedDistance = val,
                  ),
                  const SizedBox(height: 20),

                  _buildSubLabel('BUDGET RANGE (PER NIGHT)', 'Average spending preference'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Min Budget (₹)', _minBudgetController, isNumber: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Max Budget (₹)', _maxBudgetController, isNumber: true)),
                    ],
                  ),

                  _buildSubLabel('AGE PREFERENCE', 'Age match range'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Min Age', _minAgeController, isNumber: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Max Age', _maxAgeController, isNumber: true)),
                    ],
                  ),
                ], initiallyExpanded: false),
                const SizedBox(height: 8),

                _buildSection('SETTINGS', [
                  _buildHideProfileOption(),
                  _buildSwitch('Booking Alerts Enabled', _bookingAlerts, (v) => setState(() => _bookingAlerts = v)),
                  const SizedBox(height: 16),
                ], initiallyExpanded: true),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'SAVE PROFILE',
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 40),
              ],

            ),
          ),
    );
  }
}
