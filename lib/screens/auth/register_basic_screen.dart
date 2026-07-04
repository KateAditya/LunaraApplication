import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import 'otp_screen.dart';
import 'terms_condition_screen.dart';

class RegisterBasicScreen extends StatefulWidget {
  const RegisterBasicScreen({super.key});

  @override
  State<RegisterBasicScreen> createState() => _RegisterBasicScreenState();
}

class _RegisterBasicScreenState extends State<RegisterBasicScreen> {
  bool _isLoading = false;
  bool _isCitiesLoading = true;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _aadhaarController = TextEditingController();
  DateTime? _selectedDob;
  String _selectedCity = 'Mumbai';
  String _selectedGender = 'MALE';
  bool _acceptTerms = false;

  List<String> _indianCities = [
    'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad', 'Ahmedabad',
    'Chennai', 'Kolkata', 'Surat', 'Pune', 'Jaipur',
    'Lucknow', 'Kanpur', 'Nagpur', 'Indore', 'Thane',
    'Bhopal', 'Visakhapatnam', 'Pimpri-Chinchwad', 'Patna', 'Vadodara',
  ];

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await ApiService.fetchCities();
      if (cities.isNotEmpty && mounted) {
        setState(() {
          _indianCities = cities;
          if (!_indianCities.contains(_selectedCity)) {
            _selectedCity = _indianCities.first;
          }
          _isCitiesLoading = false;
        });
      } else {
        if (mounted) setState(() => _isCitiesLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isCitiesLoading = false);
    }
  }

  void _showCitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            children: [
              Text(
                'SELECT CITY',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _indianCities.length,
                  itemBuilder: (context, index) {
                    final city = _indianCities[index];
                    final isSelected = city == _selectedCity;
                    return ListTile(
                      title: Text(
                        city,
                        style: TextStyle(
                          color: isSelected
                              ? LunaraTheme.primaryRich
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check,
                              color: LunaraTheme.primaryRich,
                            )
                          : null,
                      onTap: () {
                        setState(() => _selectedCity = city);
                        Navigator.pop(context);
                      },
                    );
                  },
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 40),
              _buildProgressBar(),
              const SizedBox(height: 40),
              Text(
                'THE ADVENTURE BEGINS',
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'CREATE ACCOUNT',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 32,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 40),
              _buildInputLabel('FIRST NAME', true),
              _buildLightInput(
                controller: _firstNameController,
                hint: 'Enter your first name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 24),
              _buildInputLabel('LAST NAME', true),
              _buildLightInput(
                controller: _lastNameController,
                hint: 'Enter your last name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 24),
              _buildInputLabel('EMAIL ADDRESS', true),
              _buildLightInput(
                controller: _emailController,
                hint: 'Enter your email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),
              _buildInputLabel('PHONE NUMBER', true),
              _buildLightInput(
                controller: _phoneController,
                hint: '10-digit number',
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
                prefixText: '+91 ',
                maxLength: 10,
              ),
              const SizedBox(height: 24),
              _buildInputLabel('DATE OF BIRTH', true),
              GestureDetector(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate:
                        _selectedDob ??
                        DateTime.now().subtract(const Duration(days: 365 * 18)),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: LunaraTheme.primaryRich,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null && picked != _selectedDob) {
                    setState(() {
                      _selectedDob = picked;
                      _dobController.text =
                          "${picked.day}/${picked.month}/${picked.year}";
                    });
                  }
                },
                child: AbsorbPointer(
                  child: _buildLightInput(
                    controller: _dobController,
                    hint: 'DD/MM/YYYY',
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildInputLabel('GENDER', true),
              _buildGenderSelector(),
              const SizedBox(height: 24),
              _buildInputLabel('CITY', true),
              _buildCitySelector(),
              const SizedBox(height: 24),
              _buildInputLabel('AADHAAR NUMBER (OPTIONAL)', false),
              _buildLightInput(
                controller: _aadhaarController,
                hint: '12-digit number',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 40),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _acceptTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptTerms = value ?? false;
                        });
                      },
                      activeColor: LunaraTheme.primaryRich,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TermsConditionScreen(),
                          ),
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          text: 'I accept the ',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87),
                          ),
                          children: const [
                            TextSpan(
                              text: 'terms & conditions',
                              style: TextStyle(
                                fontSize: 14,
                                color: LunaraTheme.primaryRich,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.primaryRich,
                      ),
                    )
                  : LunaraActionButton(
                      text: 'NEXT STEP',
                      onPressed: () async {
                        String? errorMessage;
                        if (_firstNameController.text.trim().isEmpty) {
                          errorMessage = 'Please enter your first name';
                        } else if (_lastNameController.text.trim().isEmpty) {
                          errorMessage = 'Please enter your last name';
                        } else if (_emailController.text.trim().isEmpty || !_emailController.text.contains('@')) {
                          errorMessage = 'Please enter a valid email address';
                        } else if (_phoneController.text.trim().isEmpty) {
                          errorMessage = 'Please enter your phone number';
                        } else if (_selectedDob == null) {
                          errorMessage = 'Please select your date of birth';
                        } else if (_selectedGender.isEmpty) {
                          errorMessage = 'Please select your gender';
                        } else if (_selectedCity.isEmpty) {
                          errorMessage = 'Please select your city';
                        } else if (!_acceptTerms) {
                          errorMessage = 'Please accept the terms & conditions';
                        }

                        if (errorMessage != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errorMessage),
                              backgroundColor: LunaraTheme.primaryDeep,
                            ),
                          );
                          return;
                        }

                        setState(() => _isLoading = true);
                        
                        final emailError = await AuthService.checkEmail(_emailController.text.trim());
                        if (emailError != null) {
                          if (!mounted) return;
                          setState(() => _isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(emailError),
                              backgroundColor: LunaraTheme.primaryDeep,
                            ),
                          );
                          return;
                        }

                        final error = await AuthService.sendOtp(
                          _phoneController.text.trim(),
                        );

                        if (!mounted) return;
                        setState(() => _isLoading = false);

                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error),
                              backgroundColor: LunaraTheme.primaryDeep,
                            ),
                          );
                          return;
                        }

                        int age = 18;
                        if (_selectedDob != null) {
                          age = DateTime.now().year - _selectedDob!.year;
                        }

                        final data = {
                          'firstName': _firstNameController.text.trim(),
                          'lastName': _lastNameController.text.trim(),
                          'email': _emailController.text.trim(),
                          'phone': _phoneController.text.trim(),
                          'dob': _selectedDob?.toIso8601String(),
                          'aadhaarNo': _aadhaarController.text.trim(),
                          'profile': {
                            'displayName':
                                '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
                            'gender': _selectedGender,
                            'city': _selectedCity,
                          },
                          'preferences': {'minAgePreference': age},
                        };

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OtpScreen(
                              isRegistration: true,
                              collectedData: data,
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
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
        _progressSegment(active: true, label: 'INFO'),
        const SizedBox(width: 8),
        _progressSegment(active: false, label: 'VERIFY'),
        const SizedBox(width: 8),
        _progressSegment(active: false, label: 'SECURE'),
      ],
    );
  }

  Widget _progressSegment({required bool active, required String label}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: active
                  ? LunaraTheme.primaryRich
                  : LunaraTheme.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label, [bool isRequired = false]) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: RichText(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLightInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? prefixText,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LunaraTheme.lightBorder),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          prefixStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87), fontSize: 16),
          counterText: '',
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
          border: InputBorder.none,
          icon: Icon(icon, color: LunaraTheme.primaryRich, size: 20),
        ),
      ),
    );
  }

  Widget _buildCitySelector() {
    return GestureDetector(
      onTap: _showCitySelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LunaraTheme.lightBorder),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_city_outlined,
            color: LunaraTheme.primaryRich,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _selectedCity,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87)),
            ),
          ),
          Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
        ],
      ),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Row(
      children: [
        _genderCard('MALE', Icons.male, _selectedGender == 'MALE'),
        const SizedBox(width: 12),
        _genderCard('FEMALE', Icons.female, _selectedGender == 'FEMALE'),
        const SizedBox(width: 12),
        _genderCard('OTHER', Icons.transgender, _selectedGender == 'OTHER'),
      ],
    );
  }

  Widget _genderCard(String label, IconData icon, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedGender = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? LunaraTheme.primaryRich.withValues(alpha: 0.05)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? LunaraTheme.primaryRich
                  : LunaraTheme.lightBorder,
            ),
            boxShadow: isSelected ? null : LunaraTheme.premiumShadow,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? LunaraTheme.primaryRich
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
