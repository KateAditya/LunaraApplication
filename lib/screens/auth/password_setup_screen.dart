import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/top_error_banner.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/onboarding_service.dart';
import '../profile_setup/selfie_verification_screen.dart';

class PasswordSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const PasswordSetupScreen({super.key, this.collectedData});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  bool _useBiometrics = false;
  bool _biometricsAvailable = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _passwordError;

  void _validatePasswords() {
    if (_passwordController.text.isNotEmpty &&
        _passwordController.text.length < 3) {
      setState(
        () => _passwordError = 'Password must contain minimum 3 characters',
      );
    } else if (_confirmController.text.isNotEmpty &&
        _passwordController.text != _confirmController.text) {
      setState(() => _passwordError = 'Passwords do not match');
    } else {
      setState(() => _passwordError = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswords);
    _confirmController.addListener(_validatePasswords);
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await BiometricService.isBiometricsAvailable();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  Future<void> _handleCompleteSetup() async {
    if (_passwordController.text.length < 3) {
      TopErrorBanner.show(context, 'Password must contain minimum 3 characters');
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      TopErrorBanner.show(context, 'Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    // Persist biometric preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', _useBiometrics);

    final error = await AuthService.registerUser(
      widget.collectedData ?? {},
      _passwordController.text,
      biometricEnabled: _useBiometrics,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        final data = widget.collectedData != null
            ? Map<String, dynamic>.from(widget.collectedData!)
            : <String, dynamic>{};
        data['password'] = _passwordController.text;

        await OnboardingService.saveProgress('selfie_verification', data);

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SelfieVerificationScreen(collectedData: data),
          ),
        );
      } else {
        TopErrorBanner.show(context, error);
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
                'SECURITY HUB',
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SET PASSWORD',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 32,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 40),
              _buildInputLabel('NEW PASSWORD'),
              _buildLightInput(
                controller: _passwordController,
                hint: 'Enter strong password',
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 24),
              _buildInputLabel('CONFIRM PASSWORD'),
              _buildLightInput(
                controller: _confirmController,
                hint: 'Repeat your password',
                icon: Icons.lock_reset_outlined,
                isPassword: true,
              ),
              if (_passwordError != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    _passwordError!,
                    style: const TextStyle(
                      color: LunaraTheme.primaryDeep,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _buildBiometricToggle(),
              const SizedBox(height: 80),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.primaryRich,
                      ),
                    )
                  : LunaraActionButton(
                      text: 'COMPLETE SETUP',
                      onPressed: _handleCompleteSetup,
                    ),
            ],
          ),
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
        _progressSegment(active: true, completed: true, label: 'INFO'),
        const SizedBox(width: 8),
        _progressSegment(active: true, completed: true, label: 'VERIFY'),
        const SizedBox(width: 8),
        _progressSegment(active: true, completed: false, label: 'SECURE'),
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
              color: completed
                  ? LunaraTheme.primaryRich
                  : active
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

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.54),
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLightInput({
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextEditingController? controller,
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
        obscureText: isPassword && _obscurePassword,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.38),
          ),
          border: InputBorder.none,
          icon: Icon(icon, color: LunaraTheme.primaryRich, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.54),
                    size: 16,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildBiometricToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _useBiometrics
              ? LunaraTheme.primaryRich.withValues(alpha: 0.6)
              : LunaraTheme.lightBorder,
          width: _useBiometrics ? 1.5 : 1.0,
        ),
        boxShadow: _useBiometrics
            ? [
                BoxShadow(
                  color: LunaraTheme.primaryRich.withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : LunaraTheme.premiumShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LunaraTheme.primaryRich.withValues(
                alpha: _useBiometrics ? 0.2 : 0.1,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.face_unlock_outlined,
              color: LunaraTheme.primaryRich,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENABLE BIOMETRICS',
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _biometricsAvailable
                      ? 'Secure access with Face ID or fingerprint'
                      : 'Not available on this device',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _useBiometrics,
            activeTrackColor: LunaraTheme.primaryRich,
            onChanged: _biometricsAvailable
                ? (value) async {
                    if (value) {
                      // Try to authenticate before enabling
                      final success = await BiometricService.authenticate(
                        reason: 'Verify your identity to enable biometrics',
                      );
                      if (!mounted) return;
                      if (success) {
                        setState(() => _useBiometrics = true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Biometric verification failed. Please try again.',
                            ),
                            backgroundColor: Colors.red.shade700,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        setState(() => _useBiometrics = false);
                      }
                    } else {
                      setState(() => _useBiometrics = false);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
