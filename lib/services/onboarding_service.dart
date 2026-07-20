import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/auth/register_basic_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/password_setup_screen.dart';
import '../screens/profile_setup/selfie_verification_screen.dart';
import '../screens/profile_setup/profile_photos_screen.dart';
import '../screens/profile_setup/profile_details_screen.dart';

class OnboardingService {
  static const String _keyStep = 'onboarding_step';
  static const String _keyData = 'onboarding_data';

  /// Save current registration step and data payload
  static Future<void> saveProgress(String step, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStep, step);
      
      // Filter out non-serializable objects if any
      final String jsonStr = jsonEncode(data);
      await prefs.setString(_keyData, jsonStr);
    } catch (e) {
      debugPrint('Error saving onboarding progress: $e');
    }
  }

  /// Retrieve saved onboarding step and data
  static Future<Map<String, dynamic>?> getSavedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? step = prefs.getString(_keyStep);
      final String? rawData = prefs.getString(_keyData);

      if (step != null && step.isNotEmpty && rawData != null) {
        final Map<String, dynamic> data = jsonDecode(rawData);
        return {
          'step': step,
          'data': data,
        };
      }
    } catch (e) {
      debugPrint('Error getting saved onboarding progress: $e');
    }
    return null;
  }

  /// Clear onboarding progress when registration completes
  static Future<void> clearProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyStep);
      await prefs.remove(_keyData);
    } catch (e) {
      debugPrint('Error clearing onboarding progress: $e');
    }
  }

  /// Map saved step name to corresponding screen widget
  static Widget getResumeScreen(String step, Map<String, dynamic> data) {
    switch (step) {
      case 'otp_verification':
        return OtpScreen(collectedData: data, isRegistration: true);
      case 'password_setup':
        return PasswordSetupScreen(collectedData: data);
      case 'selfie_verification':
        return SelfieVerificationScreen(collectedData: data);
      case 'profile_photos':
        return ProfilePhotosScreen(collectedData: data);
      case 'profile_details':
        return ProfileDetailsScreen(collectedData: data);
      case 'register_basic':
      default:
        return const RegisterBasicScreen();
    }
  }
}
