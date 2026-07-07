import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../services/auth_service.dart';
import 'password_setup_screen.dart';
import 'reset_password_screen.dart';

class OtpScreen extends StatefulWidget {
  final bool isRegistration;
  final Map<String, dynamic>? collectedData;

  const OtpScreen({super.key, this.isRegistration = true, this.collectedData});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _pulseController;
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 40),
              if (widget.isRegistration) _buildProgressBar(),
              const SizedBox(height: 40),
              Text(
                'VERIFICATION',
                style: LunaraTheme.bodyStyle.copyWith(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ENTER OTP',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 32,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a 4-digit code to your registered mobile number.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54), height: 1.5),
              ),
              const SizedBox(height: 60),
              _buildOtpFields(),
              const SizedBox(height: 40),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text(
                    'RESEND CODE IN 00:59',
                    style: TextStyle(
                      color: LunaraTheme.primaryRich,
                      letterSpacing: 1.5,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.primaryRich,
                      ),
                    )
                  : LunaraActionButton(
                      text: 'VERIFY',
                      onPressed: () async {
                        String otp = _controllers.map((c) => c.text).join();
                        if (otp.length != 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid 4-digit OTP'),
                            ),
                          );
                          return;
                        }

                        String phone = widget.collectedData?['phone'] ?? '';
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Phone number missing'),
                            ),
                          );
                          return;
                        }

                        setState(() => _isLoading = true);
                        final error = await AuthService.verifyOtp(phone, otp);

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

                        if (widget.isRegistration) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PasswordSetupScreen(
                                collectedData: widget.collectedData,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResetPasswordScreen(
                                phone: phone,
                                otp: otp,
                              ),
                            ),
                          );
                        }
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
        _progressSegment(active: true, completed: true, label: 'INFO'),
        const SizedBox(width: 8),
        _progressSegment(active: true, completed: false, label: 'VERIFY'),
        const SizedBox(width: 8),
        _progressSegment(active: false, completed: false, label: 'SECURE'),
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

  Widget _buildOtpFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, (index) => _buildOtpBox(index)),
    );
  }

  Widget _buildOtpBox(int index) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 70,
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focusNodes[index].hasFocus
                  ? LunaraTheme.primaryRich.withValues(
                      alpha: 0.5 + (_pulseController.value * 0.5),
                    )
                  : LunaraTheme.lightBorder,
              width: 2,
            ),
            boxShadow: [
              if (_focusNodes[index].hasFocus)
                BoxShadow(
                  color: LunaraTheme.primaryRich.withValues(
                    alpha: 0.2 * _pulseController.value,
                  ),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              else
                ...LunaraTheme.premiumShadow,
            ],
          ),
          child: Center(
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              onChanged: (value) {
                if (value.isNotEmpty && index < 3) {
                  _focusNodes[index + 1].requestFocus();
                } else if (value.isEmpty && index > 0) {
                  _focusNodes[index - 1].requestFocus();
                }
              },
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        );
      },
    );
  }
}
