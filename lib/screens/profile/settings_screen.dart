import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/help_article.dart';
import '../../models/community_guideline.dart';
import '../../models/legal_document.dart';
import '../../services/biometric_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'edit_profile_screen.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../../models/user.dart';
import '../../services/onboarding_service.dart';
import '../onboarding/welcome_carousel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hideProfile = false;
  bool _isLoading = true;
  bool _pushNotifications = true;
  bool _biometricAuth = false;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final user = await ApiService.fetchProfile();

    if (mounted) {
      setState(() {
        _currentUser = user;
        _biometricAuth = prefs.getBool('biometric_enabled') ?? false;

        if (user != null) {
          // If showMeInMatching is false, then profile is hidden
          _hideProfile = !user.showMeInMatching;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  _buildSectionHeader('ACCOUNT & SECURITY'),
                  const SizedBox(height: 16),
                  _buildSettingsTile(
                    'Edit Profile',
                    Icons.person_outline,
                    () async {
                      if (_currentUser == null) {
                        setState(() => _isLoading = true);
                        _currentUser = await ApiService.fetchProfile();
                        setState(() => _isLoading = false);
                      }
                      if (_currentUser != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditProfileScreen(user: _currentUser!),
                          ),
                        ).then((_) => _loadSettings());
                      }
                    },
                  ),
                  _buildSettingsTile(
                    'Change Password',
                    Icons.lock_outline,
                    () => _showChangePasswordSheet(),
                  ),
                  _buildSwitchTile('Biometric Authentication', _biometricAuth, (
                    v,
                  ) async {
                    final prefs = await SharedPreferences.getInstance();

                    if (v) {
                      // Attempt to authenticate before turning on
                      final success = await BiometricService.authenticate(
                        reason: 'Verify your identity to enable biometrics',
                      );
                      if (success) {
                        await prefs.setBool('biometric_enabled', true);
                        setState(() => _biometricAuth = true);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Biometric authentication failed.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } else {
                      // Require authentication to disable it
                      final success = await BiometricService.authenticate(
                        reason: 'Verify your identity to disable biometrics',
                      );
                      if (success) {
                        await prefs.setBool('biometric_enabled', false);
                        setState(() => _biometricAuth = false);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Verification failed. Cannot disable.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        // Revert switch to true visually since they failed to disable
                        setState(() => _biometricAuth = true);
                      }
                    }
                  }),
                  const SizedBox(height: 40),
                  _buildSectionHeader('PRIVACY'),
                  const SizedBox(height: 16),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: LunaraTheme.electricViolet,
                            ),
                          ),
                        )
                      : _buildHideProfileTile(),
                  _buildSettingsTile(
                    'Blocked Contacts',
                    Icons.block_flipped,
                    () => _showBlockedContactsSheet(),
                  ),
                  _buildSettingsTile(
                    'Data & Permissions',
                    Icons.data_usage_outlined,
                    () => _showDataPermissionsSheet(),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionHeader('NOTIFICATIONS'),
                  const SizedBox(height: 16),
                  _buildSwitchTile(
                    'Push Notifications',
                    _pushNotifications,
                    (v) => setState(() => _pushNotifications = v),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionHeader('SUPPORT & LEGAL'),
                  const SizedBox(height: 16),
                  _buildSettingsTile(
                    'Help Center',
                    Icons.help_outline,
                    () => _showHelpCenterSheet(),
                  ),
                  _buildSettingsTile(
                    'Community Guidelines',
                    Icons.groups_outlined,
                    () => _showCommunityGuidelinesSheet(),
                  ),
                  _buildSettingsTile(
                    'Legal & Terms',
                    Icons.gavel_outlined,
                    () => _showLegalDocumentsSheet(),
                  ),
                  const SizedBox(height: 40),
                  _buildDangerZone(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'SETTINGS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.black,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildSettingsTile(String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.black, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[300], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: LunaraTheme.premiumCardShadow,
          border: Border.all(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: LunaraTheme.electricViolet.withValues(
                alpha: 0.3,
              ),
              activeColor: LunaraTheme.electricViolet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHideProfileTile() {
    final isProUser = _currentUser?.isPro ?? false;

    if (isProUser) {
      return _buildSwitchTile('Hide Profile', _hideProfile, (v) async {
        final prevValue = _hideProfile;
        setState(() => _hideProfile = v);

        final success = await ApiService.updateUserPreferences(
          showMeInMatching: !v,
        );

        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update profile visibility.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _hideProfile = prevValue);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                v ? 'Profile is now hidden.' : 'Profile is now visible.',
              ),
              backgroundColor: LunaraTheme.electricViolet,
            ),
          );
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          showSubscriptionLimitDialog(
            context,
            feature: SubLimitFeature.hideProfile,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.visibility_off_outlined,
                color: Colors.black,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        'Hide Profile',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                        child: Text(
                          'VIP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showSubscriptionLimitDialog(
                    context,
                    feature: SubLimitFeature.hideProfile,
                  );
                },
                icon: const Icon(Icons.lock, size: 12, color: Colors.white),
                label: const Text(
                  'UPGRADE TO HIDE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LunaraTheme.electricViolet,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DANGER ZONE',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () async {
            await ApiService.logout();
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeCarousel()),
                (route) => false,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: LunaraTheme.electricViolet,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'LOG OUT',
                  style: TextStyle(
                    color: LunaraTheme.electricViolet,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _showDeleteAccountDialog(),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'DELETE ACCOUNT',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Bottom sheets and dialogs ---

  void _showChangePasswordSheet() {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        bool obscureOld = true;
        bool obscureNew = true;
        bool obscureConfirm = true;

        String? oldError;
        String? newError;
        String? confirmError;

        bool isUpdating = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            void validateOld(String val) {
              setModalState(() {
                if (val.isEmpty) {
                  oldError = 'Current password is required';
                } else {
                  oldError = null;
                }
              });
            }

            void validateNew(String val) {
              setModalState(() {
                if (val.isEmpty) {
                  newError = 'New password is required';
                } else if (val.length < 6) {
                  newError = 'Password must be at least 6 characters';
                } else {
                  newError = null;
                }
              });
            }

            void validateConfirm(String val) {
              setModalState(() {
                if (val.isEmpty) {
                  confirmError = 'Please confirm your new password';
                } else if (val != newController.text) {
                  confirmError = 'Passwords do not match';
                } else {
                  confirmError = null;
                }
              });
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 40,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'CHANGE PASSWORD',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Current Password Field
                  TextField(
                    controller: oldController,
                    obscureText: obscureOld,
                    onChanged: validateOld,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      labelStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                      errorText: oldError,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[100]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 2,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: Colors.grey[400],
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureOld
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey[400],
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscureOld = !obscureOld;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // New Password Field
                  TextField(
                    controller: newController,
                    obscureText: obscureNew,
                    onChanged: (val) {
                      validateNew(val);
                      if (confirmController.text.isNotEmpty) {
                        validateConfirm(confirmController.text);
                      }
                    },
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      labelStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                      errorText: newError,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[100]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 2,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: Colors.grey[400],
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey[400],
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscureNew = !obscureNew;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password Field
                  TextField(
                    controller: confirmController,
                    obscureText: obscureConfirm,
                    onChanged: validateConfirm,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      labelStyle: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                      errorText: confirmError,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[100]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: LunaraTheme.electricViolet,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 2,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_reset,
                        color: Colors.grey[400],
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey[400],
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: isUpdating
                          ? null
                          : () async {
                              validateOld(oldController.text);
                              validateNew(newController.text);
                              validateConfirm(confirmController.text);

                              if (oldError != null ||
                                  newError != null ||
                                  confirmError != null) {
                                return;
                              }

                              if (oldController.text.isEmpty ||
                                  newController.text.isEmpty ||
                                  confirmController.text.isEmpty) {
                                return;
                              }

                              setModalState(() => isUpdating = true);

                              final success = await ApiService.changePassword(
                                oldController.text,
                                newController.text,
                                confirmController.text,
                              );

                              if (!mounted) return;
                              setModalState(() => isUpdating = false);

                              if (success) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Password updated successfully!',
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                setModalState(() {
                                  oldError = 'Incorrect current password';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to update password.'),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      child: isUpdating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'UPDATE PASSWORD',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBlockedContactsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        List<Map<String, dynamic>>? blockedUsers;
        bool isError = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (blockedUsers == null && !isError) {
              ApiService.getBlockedUsersDetails()
                  .then((list) {
                    setModalState(() {
                      blockedUsers = list;
                    });
                  })
                  .catchError((e) {
                    setModalState(() {
                      isError = true;
                    });
                  });
            }

            Widget content;
            if (isError) {
              content = Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load blocked contacts',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          isError = false;
                          blockedUsers = null;
                        });
                      },
                      child: const Text(
                        'RETRY',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else if (blockedUsers == null) {
              content = const Padding(
                padding: EdgeInsets.symmetric(vertical: 80.0),
                child: Center(
                  child: CircularProgressIndicator(
                    color: LunaraTheme.electricViolet,
                  ),
                ),
              );
            } else if (blockedUsers!.isEmpty) {
              content = Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Icon(
                        Icons.block_flipped,
                        color: Colors.grey[200],
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'No blocked contacts',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Blocked users will appear here',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              content = ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: blockedUsers!.length,
                  itemBuilder: (context, index) {
                    final user = blockedUsers![index];
                    final userId = user['id']?.toString() ?? '';
                    final firstName = user['firstName']?.toString() ?? '';
                    final lastName = user['lastName']?.toString() ?? '';
                    final fullName = '$firstName $lastName'.trim();
                    final profileImageUrl =
                        user['profileImageUrl']?.toString() ?? '';

                    bool isUnblocking = false;

                    String getFullPhotoUrl(String path) {
                      if (path.isEmpty) return '';
                      if (path.startsWith('http')) return path;
                      if (path.startsWith('/'))
                        return '${ApiService.baseUrl}$path';
                      return '${ApiService.baseUrl}/$path';
                    }

                    final photoUrl = getFullPhotoUrl(profileImageUrl);

                    return StatefulBuilder(
                      builder: (context, tileState) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LunaraTheme.cardGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: LunaraTheme.premiumCardShadow,
                            border: Border.all(
                              color: LunaraTheme.electricViolet.withValues(
                                alpha: 0.05,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey[100],
                                backgroundImage: photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              isUnblocking
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: LunaraTheme.electricViolet,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor:
                                            LunaraTheme.electricViolet,
                                        elevation: 0,
                                        side: const BorderSide(
                                          color: LunaraTheme.electricViolet,
                                          width: 1.5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: () async {
                                        tileState(() {
                                          isUnblocking = true;
                                        });

                                        final success =
                                            await ApiService.unblockUser(
                                              userId,
                                            );

                                        if (success) {
                                          setModalState(() {
                                            blockedUsers!.removeAt(index);
                                          });
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '$fullName unblocked successfully',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } else {
                                          tileState(() {
                                            isUnblocking = false;
                                          });
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Failed to unblock user',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text(
                                        'UNBLOCK',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 40,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'BLOCKED CONTACTS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),
                  content,
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDataPermissionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const PermissionsSheet();
      },
    );
  }

  void _showHelpCenterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const HelpCenterSheet();
      },
    );
  }

  void _showCommunityGuidelinesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const CommunityGuidelinesSheet();
      },
    );
  }

  void _showLegalDocumentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return const LegalDocumentsSheet();
      },
    );
  }

  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();
    String selectedReason = 'Taking a break';
    String? passwordError;
    String? apiErrorMessage;
    bool isDeleting = false;
    bool obscurePassword = true;

    final reasons = [
      'Taking a break',
      'Privacy concerns',
      'Created another account',
      'Trouble getting started',
      'Too many notifications',
      'Something else',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'DELETE ACCOUNT',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'We are sorry to see you leave. Please let us know why you are deleting your account:',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reasons list
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: reasons.map((reason) {
                        final isSelected = selectedReason == reason;
                        return ChoiceChip(
                          label: Text(
                            reason,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.bold,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: LunaraTheme.electricViolet,
                          backgroundColor: Colors.grey[100],
                          elevation: isSelected ? 2 : 0,
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() {
                                selectedReason = reason;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Red warning box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'PERMANENT ACTION',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Deleting your account will permanently purge your profile, photos, matches, chat history, tickets, and active subscriptions. This action cannot be undone.',
                            style: TextStyle(
                              color: Colors.red[900],
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password input field
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      onChanged: (_) {
                        if (passwordError != null || apiErrorMessage != null) {
                          setModalState(() {
                            passwordError = null;
                            apiErrorMessage = null;
                          });
                        }
                      },
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        labelStyle: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                        ),
                        hintText: 'Enter password to confirm',
                        errorText: passwordError,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Colors.redAccent,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.redAccent),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Colors.redAccent,
                            width: 2,
                          ),
                        ),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: Colors.grey,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setModalState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),

                    if (apiErrorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                apiErrorMessage!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: isDeleting
                                ? null
                                : () => Navigator.pop(ctx),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: isDeleting
                                ? null
                                : () async {
                                    final pwd = passwordController.text.trim();
                                    if (pwd.isEmpty) {
                                      setModalState(() {
                                        passwordError =
                                            'Password is required to confirm';
                                      });
                                      return;
                                    }

                                    setModalState(() {
                                      isDeleting = true;
                                      passwordError = null;
                                      apiErrorMessage = null;
                                    });

                                    final result =
                                        await ApiService.deleteAccount(
                                          password: pwd,
                                          reason: selectedReason,
                                        );

                                    if (!mounted) return;

                                    if (result['success'] == true) {
                                      // Perform stateful immediate logout cleanup
                                      await OnboardingService.clearProgress();
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.clear();

                                      if (mounted) {
                                        Navigator.pop(ctx); // Close modal
                                        Navigator.pushAndRemoveUntil(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const WelcomeCarousel(),
                                          ),
                                          (route) => false,
                                        );

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Your Lunara account has been permanently deleted.',
                                            ),
                                            backgroundColor: Colors.redAccent,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } else {
                                      setModalState(() {
                                        isDeleting = false;
                                        if (result['code'] ==
                                                'INVALID_PASSWORD' ||
                                            result['code'] ==
                                                'PASSWORD_REQUIRED') {
                                          passwordError =
                                              result['message'] ??
                                              'Incorrect password';
                                        } else {
                                          apiErrorMessage =
                                              result['message'] ??
                                              'Failed to delete account';
                                        }
                                      });
                                    }
                                  },
                            child: isDeleting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'DELETE ACCOUNT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class HelpCenterSheet extends StatefulWidget {
  const HelpCenterSheet({super.key});

  @override
  State<HelpCenterSheet> createState() => _HelpCenterSheetState();
}

class _HelpCenterSheetState extends State<HelpCenterSheet> {
  late Future<List<HelpArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchHelpCenterArticles();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchHelpCenterArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'HELP CENTER',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<HelpArticle>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final articles = snapshot.data;
                if (articles == null || articles.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: articles.length,
                  itemBuilder: (context, index) {
                    final article = articles[index];
                    return _buildArticleCard(article);
                  },
                );
              },
            ),
          ),
          _buildSupportContactBar(),
        ],
      ),
    );
  }

  Widget _buildArticleCard(HelpArticle article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            article.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            article.category.toUpperCase(),
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              article.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD HELP CENTER',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO HELP ARTICLES FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Support articles will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportContactBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'STILL NEED HELP?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Get in touch with our 24/7 Support team.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildContactButton(
                  icon: Icons.mail_outline,
                  label: 'EMAIL',
                  onTap: () {
                    Clipboard.setData(
                      const ClipboardData(text: 'support@lunara.buzz'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Support email copied to clipboard!'),
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactButton(
                  icon: Icons.phone_outlined,
                  label: 'CALL',
                  onTap: () {
                    Clipboard.setData(
                      const ClipboardData(text: '+919876543210'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Support phone number copied to clipboard!',
                        ),
                        backgroundColor: LunaraTheme.electricViolet,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: LunaraTheme.electricViolet, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: LunaraTheme.electricViolet,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommunityGuidelinesSheet extends StatefulWidget {
  const CommunityGuidelinesSheet({super.key});

  @override
  State<CommunityGuidelinesSheet> createState() =>
      _CommunityGuidelinesSheetState();
}

class _CommunityGuidelinesSheetState extends State<CommunityGuidelinesSheet> {
  late Future<List<CommunityGuideline>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchCommunityGuidelines();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchCommunityGuidelines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'COMMUNITY GUIDELINES',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<CommunityGuideline>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final guidelines = snapshot.data;
                if (guidelines == null || guidelines.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: guidelines.length,
                  itemBuilder: (context, index) {
                    final guideline = guidelines[index];
                    return _buildGuidelineCard(guideline);
                  },
                );
              },
            ),
          ),
          _buildInfoBanner(),
        ],
      ),
    );
  }

  Widget _buildGuidelineCard(CommunityGuideline guideline) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            guideline.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            guideline.category.toUpperCase(),
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              guideline.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD GUIDELINES',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO GUIDELINES FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Guidelines will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.secondaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'STAY RESPECTFUL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Guidelines are in place to ensure a safe, fun, and inclusive environment for everyone. Violations may result in account suspension.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class LegalDocumentsSheet extends StatefulWidget {
  const LegalDocumentsSheet({super.key});

  @override
  State<LegalDocumentsSheet> createState() => _LegalDocumentsSheetState();
}

class _LegalDocumentsSheetState extends State<LegalDocumentsSheet> {
  late Future<List<LegalDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchLegalDocuments();
  }

  void _retry() {
    setState(() {
      _future = ApiService.fetchLegalDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'LEGAL & TERMS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<LegalDocument>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: LunaraTheme.electricViolet,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _buildErrorView();
                }
                final documents = snapshot.data;
                if (documents == null || documents.isEmpty) {
                  return _buildEmptyView();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return _buildDocumentCard(document);
                  },
                );
              },
            ),
          ),
          _buildInfoBanner(),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(LegalDocument document) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            document.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            'VERSION ${document.version} — ACTIVE',
            style: const TextStyle(
              color: LunaraTheme.electricViolet,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          iconColor: LunaraTheme.electricViolet,
          collapsedIconColor: Colors.black54,
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              document.content,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'FAILED TO LOAD LEGAL DOCUMENTS',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel_rounded, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            const Text(
              'NO LEGAL DOCUMENTS FOUND',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Legal terms will appear here once published.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'REFRESH',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LunaraTheme.amberGlow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.gavel_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'LEGAL AGREEMENT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your privacy, trust, and security are our highest priority. All documents here represent a binding legal agreement.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class PermissionsSheet extends StatefulWidget {
  const PermissionsSheet({super.key});

  @override
  State<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<PermissionsSheet>
    with WidgetsBindingObserver {
  String _locationStatus = 'Checking...';
  String _cameraStatus = 'Checking...';
  String _photoStatus = 'Checking...';
  String _notificationStatus = 'Checking...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final location = await Permission.location.status;
    final camera = await Permission.camera.status;
    final photos = await Permission.photos.status;
    final notification = await Permission.notification.status;

    if (mounted) {
      setState(() {
        _locationStatus = _getStatusText(location);
        _cameraStatus = _getStatusText(camera);
        _photoStatus = _getStatusText(photos);
        _notificationStatus = _getStatusText(notification);
      });
    }
  }

  String _getStatusText(PermissionStatus status) {
    if (status.isGranted) return 'Enabled';
    if (status.isPermanentlyDenied)
      return 'Permanently Denied (Tap to open Settings)';
    if (status.isDenied) return 'Denied (Tap to request)';
    if (status.isRestricted) return 'Restricted';
    return 'Not Determined';
  }

  Future<void> _handlePermissionTap(Permission permission) async {
    final status = await permission.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await permission.request();
      _checkPermissions();
    }
  }

  Widget _permissionTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: LunaraTheme.electricViolet, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitle.contains('Denied')
                          ? Colors.redAccent
                          : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'DATA & PERMISSIONS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 24),
          _permissionTile(
            Icons.location_on_outlined,
            'Location',
            _locationStatus,
            () => _handlePermissionTap(Permission.location),
          ),
          _permissionTile(
            Icons.camera_alt_outlined,
            'Camera',
            _cameraStatus,
            () => _handlePermissionTap(Permission.camera),
          ),
          _permissionTile(
            Icons.photo_library_outlined,
            'Photo Library',
            _photoStatus,
            () => _handlePermissionTap(Permission.photos),
          ),
          _permissionTile(
            Icons.notifications_none,
            'Notifications',
            _notificationStatus,
            () => _handlePermissionTap(Permission.notification),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
