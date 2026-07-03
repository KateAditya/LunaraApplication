import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../profile_setup/profile_photos_screen.dart';

class PasswordSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const PasswordSetupScreen({super.key, this.collectedData});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  bool _useBiometrics = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _passwordError;

  void _validatePasswords() {
    if (_passwordController.text.isNotEmpty && _passwordController.text.length < 3) {
      setState(() => _passwordError = 'Password must contain minimum 3 characters');
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
  }

  Future<void> _handleCompleteSetup() async {
    if (_passwordController.text.length < 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password must contain minimum 3 characters')));
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _isLoading = true);

    final error = await AuthService.registerUser(
      widget.collectedData ?? {},
      _passwordController.text,
      biometricEnabled: _useBiometrics,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ProfilePhotosScreen(collectedData: widget.collectedData),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: LunaraTheme.primaryDeep),
        );
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
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
      icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
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
              color: active ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
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
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
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
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)),
          border: InputBorder.none,
          icon: Icon(icon, color: LunaraTheme.primaryRich, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LunaraTheme.lightBorder),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LunaraTheme.primaryRich.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.face_unlock_outlined,
              color: LunaraTheme.primaryRich,
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
                  'Secure access with FaceID or TouchID',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _useBiometrics,
            activeTrackColor: LunaraTheme.primaryRich,
            onChanged: (value) async {
              if (value) {
                final success = await BiometricService.authenticate(
                  reason: 'Verify your identity to enable biometrics',
                );
                if (success) {
                  setState(() => _useBiometrics = true);
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Biometric authentication failed. Cannot enable.')),
                  );
                  setState(() => _useBiometrics = false);
                }
              } else {
                setState(() => _useBiometrics = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
