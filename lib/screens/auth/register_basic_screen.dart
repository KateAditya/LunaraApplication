import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/top_error_banner.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/onboarding_service.dart';
import 'otp_screen.dart';
import 'terms_screen.dart';

/// Formats a raw 12-digit string as XXXX XXXX XXXX
class _AadhaarFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 12) return oldValue;
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 4 || i == 8) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class RegisterBasicScreen extends StatefulWidget {
  const RegisterBasicScreen({super.key});

  @override
  State<RegisterBasicScreen> createState() => _RegisterBasicScreenState();
}

class _RegisterBasicScreenState extends State<RegisterBasicScreen> {
  bool _isLoading = false;
  bool _acceptedTerms = false;
  String? _aadhaarError;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _aadhaarController = TextEditingController();
  DateTime? _selectedDob;
  String _selectedCity = 'Mumbai';
  String _selectedGender = 'MALE';

  List<String> _indianCities = ['Pune'];

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
        });
      } else {
      }
    } catch (_) {
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
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.87),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
              ),
              const SizedBox(height: 24),
              _buildInputLabel('LAST NAME', true),
              _buildLightInput(
                controller: _lastNameController,
                hint: 'Enter your last name',
                icon: Icons.person_outline,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
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
                hint: 'XXXX XXXX XXXX',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                maxLength: 14, // 12 digits + 2 spaces
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, _AadhaarFormatter()],
              ),
              if (_aadhaarError != null) ...[  
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    _aadhaarError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              _buildTermsAcceptance(),
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
                        final firstName = _firstNameController.text.trim();
                        final lastName = _lastNameController.text.trim();
                        final email = _emailController.text.trim();
                        final phone = _phoneController.text.trim();

                        final nameRegex = RegExp(r'^[a-zA-Z\s]+$');

                        if (firstName.isEmpty) {
                          errorMessage = 'Please enter your first name';
                        } else if (firstName.length < 2) {
                          errorMessage = 'First name must be at least 2 characters';
                        } else if (!nameRegex.hasMatch(firstName)) {
                          errorMessage = 'First name can only contain letters (no symbols or numbers)';
                        } else if (lastName.isEmpty) {
                          errorMessage = 'Please enter your last name';
                        } else if (!nameRegex.hasMatch(lastName)) {
                          errorMessage = 'Last name can only contain letters (no symbols or numbers)';
                        } else if (email.isEmpty) {
                          errorMessage = 'Please enter your email address';
                        } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                          errorMessage = 'Please enter a valid email address';
                        } else if (phone.isEmpty) {
                          errorMessage = 'Please enter your phone number';
                        } else if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
                          errorMessage = 'Please enter a valid 10-digit Indian phone number (starting with 6–9)';
                        } else if (_selectedDob == null) {
                          errorMessage = 'Please select your date of birth';
                        } else if (_selectedGender.isEmpty) {
                          errorMessage = 'Please select your gender';
                        } else if (_selectedCity.isEmpty) {
                          errorMessage = 'Please select your city';
                        } else if (!_acceptedTerms) {
                          errorMessage = 'Please read and accept the Terms and Conditions';
                        } else {
                          // Validate Aadhaar if entered
                          final aadhaarRaw = _aadhaarController.text.replaceAll(' ', '');
                          if (aadhaarRaw.isNotEmpty) {
                            if (aadhaarRaw.length != 12 || !RegExp(r'^[2-9][0-9]{11}$').hasMatch(aadhaarRaw)) {
                              setState(() => _aadhaarError = 'Enter a valid 12-digit Aadhaar number (starting 2–9)');
                              TopErrorBanner.show(context, 'Please enter a valid Aadhaar number');
                              return;
                            } else {
                              setState(() => _aadhaarError = null);
                            }
                          }
                          // Validate age (must be >= 18)
                          final birthDate = _selectedDob!;
                          final today = DateTime.now();
                          int age = today.year - birthDate.year;
                          if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
                            age--;
                          }
                          if (age < 18) {
                            errorMessage = 'You must be at least 18 years old to register';
                          }
                        }

                        if (errorMessage != null) {
                          TopErrorBanner.show(context, errorMessage);
                          return;
                        }

                        setState(() => _isLoading = true);

                        final emailError = await AuthService.checkEmail(email);
                        if (emailError != null) {
                          if (!mounted) return;
                          setState(() => _isLoading = false);
                          TopErrorBanner.show(context, emailError);
                          return;
                        }

                        final error = await AuthService.sendOtp(phone);

                        if (!mounted) return;
                        setState(() => _isLoading = false);

                        if (error != null) {
                          TopErrorBanner.show(context, error);
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
                          'aadhaarNo': _aadhaarController.text.replaceAll(' ', '').trim(),
                          'profile': {
                            'displayName':
                                '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
                            'gender': _selectedGender,
                            'city': _selectedCity,
                          },
                          'preferences': {'minAgePreference': age},
                        };

                        await OnboardingService.saveProgress('otp_verification', data);

                        if (!mounted) return;

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

  /// Opens Terms & Conditions in a scroll-to-accept bottom sheet.
  void _showTermsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TermsScrollBottomSheet(
        onAccepted: () {
          setState(() => _acceptedTerms = true);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Widget _buildTermsAcceptance() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _acceptedTerms ? null : _showTermsBottomSheet,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _acceptedTerms
              ? LunaraTheme.primaryRich.withValues(alpha: isDark ? 0.15 : 0.06)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _acceptedTerms
                ? LunaraTheme.primaryRich.withValues(alpha: 0.6)
                : LunaraTheme.lightBorder,
            width: _acceptedTerms ? 1.5 : 1.0,
          ),
          boxShadow: LunaraTheme.premiumShadow,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _acceptedTerms
                    ? LunaraTheme.primaryRich
                    : Colors.transparent,
                border: Border.all(
                  color: _acceptedTerms
                      ? LunaraTheme.primaryRich
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: _acceptedTerms
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : const Icon(Icons.article_outlined, size: 14,
                      color: Colors.transparent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _acceptedTerms
                        ? 'Terms & Conditions Accepted'
                        : 'Read & Accept Terms',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _acceptedTerms
                          ? LunaraTheme.primaryRich
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (!_acceptedTerms)
                    Text(
                      'Tap to read and accept our Privacy Policy',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.54),
                      ),
                    ),
                ],
              ),
            ),
            if (!_acceptedTerms)
              Icon(
                Icons.chevron_right_rounded,
                color: LunaraTheme.primaryRich,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.arrow_back,
        color: Theme.of(context).colorScheme.onSurface,
      ),
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
              color: active ? LunaraTheme.primaryRich : LunaraTheme.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active
                  ? LunaraTheme.primaryRich
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.38),
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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.54),
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
          prefixStyle: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.87),
            fontSize: 16,
          ),
          counterText: '',
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
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
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.87),
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
            ),
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
                color: isSelected
                    ? LunaraTheme.primaryRich
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
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
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scroll-to-accept bottom sheet for Terms & Conditions.
/// The "I Agree" button is locked until the user scrolls to the bottom.
class _TermsScrollBottomSheet extends StatefulWidget {
  final VoidCallback onAccepted;
  const _TermsScrollBottomSheet({required this.onAccepted});

  @override
  State<_TermsScrollBottomSheet> createState() => _TermsScrollBottomSheetState();
}

class _TermsScrollBottomSheetState extends State<_TermsScrollBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _canAccept = false;
  String _termsContent = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    final doc = await ApiService.fetchLegalDocumentByType('terms_of_service');
    if (mounted) {
      setState(() {
        _termsContent = doc?.content ?? 'Failed to load Terms and Conditions. Please try again later.';
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      if (!_canAccept && !_isLoading) {
        setState(() => _canAccept = true);
      }
      return;
    }
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 40 || pos.maxScrollExtent <= 0;
    if (atBottom && !_canAccept) setState(() => _canAccept = true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sheetScrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle + Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.article_outlined,
                            color: LunaraTheme.primaryRich),
                        const SizedBox(width: 10),
                        Text(
                          'Terms & Conditions',
                          style: LunaraTheme.headingStyle.copyWith(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scroll to the bottom to accept',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.withValues(alpha: 0.2)),
                  ],
                ),
              ),
              // Scrollable terms content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: LunaraTheme.primaryRich,
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: Text(
                          _termsContent,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82),
                          ),
                        ),
                      ),
              ),
              // Accept button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    children: [
                      if (!_canAccept)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.keyboard_arrow_down_rounded,
                                  color: LunaraTheme.primaryRich, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                'Scroll down to enable acceptance',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: LunaraTheme.primaryRich,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        AnimatedOpacity(
                          opacity: _canAccept ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 300),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _canAccept ? widget.onAccepted : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: LunaraTheme.primaryRich,
                                disabledBackgroundColor:
                                    LunaraTheme.primaryRich.withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'I AGREE & ACCEPT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }
