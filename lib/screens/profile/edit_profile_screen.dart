import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';

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

  Future<void> _deletePhoto() async {
    String? photoId;
    if (_localPhotoDetails.isNotEmpty) {
      photoId = _localPhotoDetails.first['id'];
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
    final success = await ApiService.deleteProfilePhoto(photoId);
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) {
         _photoDeleted = true;
         _localProfilePhotoBytes = null;
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (success) {
      await _refreshProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo deleted successfully!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete photo.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickAndUploadPhoto({bool isMainProfilePhoto = true}) async {
    try {
      List<XFile> images = [];
      if (isMainProfilePhoto) {
        final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 50,
        );
        if (image != null) images.add(image);
      } else {
        images = await _picker.pickMultiImage(
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 50,
        );
      }

      if (images.isEmpty) return;

      setState(() => _isLoading = true);

      final List<Uint8List> bytesList = [];
      final List<String> namesList = [];
      for (var image in images) {
        final bytes = await image.readAsBytes();
        if (bytes.length > 500 * 1024) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image "${image.name}" exceeds the 500KB limit (actual size: ${(bytes.length / 1024).toStringAsFixed(1)}KB).'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
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
    final updatedUser = await ApiService.fetchProfile(userId: widget.user.id);
    if (updatedUser != null && mounted) {
       setState(() {
         _localPhotoDetails = List.from(updatedUser.photoDetails);
         _currentProfilePhotoUrl = updatedUser.profilePhoto;
         _localProfilePhotoBytes = null;
       });
    }
  }

  Future<void> _deleteOtherPhoto(String photoId) async {
    setState(() => _isLoading = true);
    final success = await ApiService.deleteProfilePhoto(photoId);
    
    if (!mounted) return;
    
    if (success) {
       await _refreshProfileData();
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Photo deleted successfully!'), backgroundColor: Colors.green),
       );
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Failed to delete photo.'), backgroundColor: Colors.red),
       );
    }
    setState(() => _isLoading = false);
  }

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

  List<String> _parseList(String val) => 
      val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    final Map<String, dynamic> data = {
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'dateOfBirth': _dobController.text.trim(),
      'gender': _genderController.text.trim(),
      'city': _cityController.text.trim(),
      'bio': _bioController.text.trim(),
      'lookingFor': _parseList(_lookingForController.text),
      'musicPreference': _parseList(_musicController.text),
      'smokingPreference': _smokingController.text.trim(),
      'drinkPreference': _parseList(_drinkController.text),
      'occupation': _occupationController.text.trim(),
      'education': _educationController.text.trim(),
      'minBudget': int.tryParse(_minBudgetController.text.trim()),
      'maxBudget': int.tryParse(_maxBudgetController.text.trim()),
      'preferredGenders': _parseList(_prefGendersController.text),
      'minAgePreference': int.tryParse(_minAgeController.text.trim()),
      'maxAgePreference': int.tryParse(_maxAgeController.text.trim()),
      'matchDistanceKm': int.tryParse(_matchDistanceController.text.trim()),
      'invisibleMode': _invisibleMode,
      'bookingAlertsEnabled': _bookingAlerts,
    };
    
    data.removeWhere((key, value) => value == null || value == '' || (value is List && value.isEmpty));
    
    final success = await ApiService.updateProfile(data);
    
    setState(() => _isLoading = false);
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update profile.'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
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
    final otherPhotos = _localPhotoDetails.length > 1 ? _localPhotoDetails.skip(1).toList() : <Map<String, String>>[];
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: otherPhotos.length + 1,
      itemBuilder: (context, index) {
        if (index == otherPhotos.length) {
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
        
        final photo = otherPhotos[index];
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: NetworkImage(photo['url'] ?? ''),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _deleteOtherPhoto(photo['id'] ?? ''),
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
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Profile picture must be less than 500 KB',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                _buildSection('PHOTOS', [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: LunaraTheme.electricViolet),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Each photo must be less than 500 KB.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildOtherPhotosGrid(),
                ], initiallyExpanded: true),
                const SizedBox(height: 8),

                _buildSection('BASIC INFO', [
                  _buildTextField('First Name', _firstNameController),
                  _buildTextField('Last Name', _lastNameController),
                  _buildTextField('Phone', _phoneController),
                  _buildTextField('Date of Birth (YYYY-MM-DD)', _dobController),
                  _buildTextField('Gender', _genderController),
                  _buildTextField('City', _cityController),
                  _buildTextField('Bio', _bioController, maxLines: 3),
                ], initiallyExpanded: true),
                const SizedBox(height: 8),
                
                _buildSection('PREFERENCES & LIFESTYLE', [
                  _buildTextField('Looking For (comma separated)', _lookingForController),
                  _buildTextField('Music Preference (comma separated)', _musicController),
                  _buildTextField('Smoking Preference', _smokingController),
                  _buildTextField('Drink Preference (comma separated)', _drinkController),
                ], initiallyExpanded: false),
                const SizedBox(height: 8),

                _buildSection('WORK & EDUCATION', [
                  _buildTextField('Occupation', _occupationController),
                  _buildTextField('Education', _educationController),
                ], initiallyExpanded: false),
                const SizedBox(height: 8),

                _buildSection('MATCHING & BUDGET', [
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Min Budget', _minBudgetController, isNumber: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Max Budget', _maxBudgetController, isNumber: true)),
                    ],
                  ),
                  _buildTextField('Preferred Genders (comma separated)', _prefGendersController),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Min Age', _minAgeController, isNumber: true)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Max Age', _maxAgeController, isNumber: true)),
                    ],
                  ),
                  _buildTextField('Match Distance (km)', _matchDistanceController, isNumber: true),
                ], initiallyExpanded: false),
                const SizedBox(height: 8),

                _buildSection('SETTINGS', [
                  _buildSwitch('Hide Profile', _invisibleMode, (v) => setState(() => _invisibleMode = v)),
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
