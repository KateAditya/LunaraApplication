import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../screens/home/dashboard.dart';
import 'top_error_banner.dart';

class FacebookLoginDialog extends StatefulWidget {
  const FacebookLoginDialog({super.key});

  static Future<void> show(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const FacebookLoginDialog(),
    );
  }

  @override
  State<FacebookLoginDialog> createState() => _FacebookLoginDialogState();
}

class _FacebookLoginDialogState extends State<FacebookLoginDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleFacebookSubmit() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty) {
      TopErrorBanner.show(context, 'Please enter your Facebook email or phone number');
      return;
    }

    final nameParts = name.isNotEmpty ? name.split(' ') : ['Facebook', 'User'];
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'User';

    // Generate deterministic Facebook ID based on email
    final cleanEmail = email.toLowerCase();
    final fbId = 'fb_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    setState(() => _isLoading = true);

    final error = await AuthService.loginWithFacebook(
      facebookId: fbId,
      email: cleanEmail.contains('@') ? cleanEmail : '$cleanEmail@facebook.com',
      firstName: firstName,
      lastName: lastName,
      avatarUrl: 'https://graph.facebook.com/$fbId/picture?type=large',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      Navigator.of(context).pop(); // Close dialog
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const Dashboard()),
        (route) => false,
      );
    } else {
      TopErrorBanner.show(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Facebook Header Branding
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1877F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.facebook, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Facebook Sign In',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1877F2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Log in with your Facebook account credentials',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              // Email / Phone field
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 14, color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'FACEBOOK EMAIL OR MOBILE',
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                  hintText: 'alex@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1877F2)),
                  filled: true,
                  fillColor: const Color(0xFFF7F9FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF1877F2), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Full Name field
              TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 14, color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'FULL NAME (OPTIONAL)',
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                  hintText: 'Alex Morgan',
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF1877F2)),
                  filled: true,
                  fillColor: const Color(0xFFF7F9FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF1877F2), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleFacebookSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1877F2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'LOG IN WITH FACEBOOK',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
