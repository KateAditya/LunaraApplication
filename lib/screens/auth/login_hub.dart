import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../services/auth_service.dart';
import '../home/dashboard.dart';
import 'register_basic_screen.dart';
import 'phone_login_screen.dart';
import 'forgot_password_screen.dart';

class LoginHub extends StatefulWidget {
  const LoginHub({super.key});

  @override
  State<LoginHub> createState() => _LoginHubState();
}

class _LoginHubState extends State<LoginHub> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter both email and password');
      return;
    }

    if (!_isValidEmail(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    final error = await AuthService.login(email, password);

    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const Dashboard()),
          (route) => false,
        );
      } else {
        _showError(error);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Hero(
                  tag: 'lunara_logo',
                  child: Image.asset(
                    LunaraTheme.logoIcon,
                    height: 120,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'MEET • EXPLORE • EXPERIENCE',
                  style: TextStyle(fontSize: 13, letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 48),
                _buildTextField(
                  label: 'EMAIL ADDRESS',
                  controller: _emailController,
                  hint: 'your@email.com',
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'PASSWORD',
                  controller: _passwordController,
                  hint: '••••••••',
                  obscureText: _obscurePassword,
                  style: const TextStyle(fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.black),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                    child: const Text('Forgot Password?', style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
                LunaraActionButton(
                  text: 'LOG IN',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("DON'T HAVE AN ACCOUNT? ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterBasicScreen())),
                      child: const Text('REGISTER NOW', style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    TextStyle? style,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: style?.letterSpacing ?? 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F2FF), // Light lavender/purple tint
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.15)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: style ?? const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: style?.copyWith(
                color: Colors.black26,
                fontWeight: FontWeight.normal,
              ) ?? const TextStyle(
                color: Colors.black26,
                fontWeight: FontWeight.normal,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}
