import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'push_notification_service.dart';
import 'package:http_parser/http_parser.dart';

class AuthService {
  /// Sends the fully assembled profile data from the onboarding flow to the backend.
  static Future<bool> setupProfile(Map<String, dynamic> combinedData) async {
    try {
      final userId = ApiService.currentUserId;
      if (userId != null) {
        combinedData['userId'] = userId;
      }
      
      final response = await ApiService.put(
        '/api/mobile/user/profile-setup',
        body: combinedData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('Profile setup successful!');
          return true;
        }
      }

      debugPrint('Profile setup failed with status: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('Error in setupProfile: $e');
      return false;
    }
  }

  /// Uploads user profile photos.
  static Future<bool> uploadPhotos(List<String> photoPaths) async {
    try {
      final userId = ApiService.currentUserId;
      if (userId == null) {
        debugPrint('Cannot upload photos: userId is null');
        return false;
      }

      final files = <http.MultipartFile>[];
      for (var path in photoPaths) {
        if (kIsWeb) {
          try {
            final response = await http.get(Uri.parse(path));
            if (response.statusCode == 200) {
              final filename = path.split('/').last;
              files.add(
                http.MultipartFile.fromBytes(
                  'photos',
                  response.bodyBytes,
                  filename: filename.contains('.') ? filename : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
                  contentType: MediaType('image', 'jpeg'),
                ),
              );
            } else {
              debugPrint('Failed to fetch image bytes from blob: ${response.statusCode}');
            }
          } catch (e) {
            debugPrint('Error fetching blob bytes: $e');
          }
        } else {
          files.add(await http.MultipartFile.fromPath(
            'photos', 
            path,
            contentType: MediaType('image', 'jpeg'),
          ));
        }
      }

      final response = await ApiService.postMultipart(
        '/api/mobile/user/photos',
        fields: {'userId': userId, 'isPrimary': 'true'},
        files: files,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true || data['status'] == 200 || data['status'] == 201) {
          debugPrint('Photos uploaded successfully!');
          return true;
        }
      }

      debugPrint('Photo upload failed with status: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error in uploadPhotos: $e');
      return false;
    }
  }

  /// Logs in the user and stores the JWT token
  /// Returns null on success, or an error message on failure.
  static Future<String?> login(String email, String password) async {
    try {
      final response = await ApiService.post(
        '/api/auth/login',
        body: {'email': email, 'password': password},
      );

      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true && respData['data'] != null) {
          final token = respData['data']['accessToken'];
          if (token != null) {
            await ApiService.setAuthToken(token);
            // Register FCM token after successful login
            PushNotificationService.registerTokenAfterLogin();
            return null; // Success
          }
        }
      }

      // Try to extract error message from response
      final errorMsg =
          respData['message'] ??
          respData['error'] ??
          'Login failed. Please check your credentials.';
      debugPrint('Login failed: $errorMsg');
      return errorMsg;
    } catch (e) {
      debugPrint('Error in login: $e');
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Refreshes the JWT token
  static Future<bool> refreshToken() async {
    try {
      final response = await ApiService.post('/api/auth/refresh');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final respData = jsonDecode(response.body);
        if (respData['success'] == true && respData['data'] != null) {
          final token = respData['data']['accessToken'];
          if (token != null) {
            await ApiService.setAuthToken(token);
            return true;
          }
        }
      }
      debugPrint('Token refresh failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return false;
    }
  }

  static Future<String?> checkEmail(String email) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/check-email',
        body: {'email': email},
      );
      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true && respData['isTaken'] == true) {
          return 'Email address is already taken by another user.';
        }
        return null; // Success (not taken)
      }
      return respData['message'] ?? respData['error'] ?? 'Failed to check email.';
    } catch (e) {
      debugPrint('Error in checkEmail: $e');
      return 'An unexpected error occurred while checking email.';
    }
  }

  static Future<String?> sendOtp(String phone) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/send-otp',
        body: {'phone': phone},
      );
      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true ||
            respData['status'] == 200 ||
            respData['message'] == 'OTP sent successfully') {
          return null; // Success
        }
      }
      return respData['message'] ?? respData['error'] ?? 'Failed to send OTP.';
    } catch (e) {
      debugPrint('Error in sendOtp: $e');
      return 'An unexpected error occurred while sending OTP.';
    }
  }

  static Future<String?> forgotPassword(String phone) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/forgot-password',
        body: {'phone': phone},
      );
      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // Success
      }
      return respData['message'] ?? respData['error'] ?? 'Failed to send reset code.';
    } catch (e) {
      debugPrint('Error in forgotPassword: $e');
      return 'An unexpected error occurred while sending reset code.';
    }
  }

  static Future<String?> resetPassword(String phone, String otp, String newPassword) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/reset-password',
        body: {
          'phone': phone,
          'otp': otp,
          'newPassword': newPassword,
        },
      );
      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // Success
      }
      return respData['message'] ?? respData['error'] ?? 'Failed to reset password.';
    } catch (e) {
      debugPrint('Error in resetPassword: $e');
      return 'An unexpected error occurred while resetting password.';
    }
  }

  static Future<String?> verifyOtp(String phone, String otp, {String? purpose}) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/verify-otp',
        body: {
          'phone': phone,
          'otp': otp,
          'purpose':? purpose,
        },
      );
      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true ||
            respData['status'] == 200 ||
            respData['message'] == 'OTP verified successfully') {
          return null; // Success
        }
      }
      return respData['message'] ?? respData['error'] ?? 'Invalid OTP.';
    } catch (e) {
      debugPrint('Error in verifyOtp: $e');
      return 'An unexpected error occurred while verifying OTP.';
    }
  }

  /// Registers a new user
  /// Returns null on success, or an error message on failure.
  static Future<String?> registerUser(
    Map<String, dynamic> data,
    String password, {
    bool biometricEnabled = false,
  }) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/register',
        body: {
          'firstName': data['firstName'],
          'lastName': data['lastName'],
          'phone': data['phone'],
          'email': data['email'],
          'dateOfBirth': data['dob'],
          'gender': data['profile']?['gender'],
          'city': data['profile']?['city'],
          'password': password,
          'biometricEnabled': biometricEnabled,
        },
      );

      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true ||
            respData['status'] == 200 ||
            respData['status'] == 201) {
          if (respData['data'] != null) {
            final token =
                respData['data']['accessToken'] ?? respData['data']['token'];
            if (token != null) {
              await ApiService.setAuthToken(token);
              // Register FCM token after successful registration
              PushNotificationService.registerTokenAfterLogin();
            }
          }
          return null; // Success
        }
      }

      final errorMsg =
          respData['message'] ?? respData['error'] ?? 'Registration failed.';
      debugPrint('Registration failed: $errorMsg');
      return errorMsg;
    } catch (e) {
      debugPrint('Error in registerUser: $e');
      return 'An unexpected error occurred during registration.';
    }
  }

  /// Log in or register with Facebook credentials
  static Future<String?> loginWithFacebook({
    required String facebookId,
    String? email,
    String? firstName,
    String? lastName,
    String? avatarUrl,
  }) async {
    try {
      final response = await ApiService.post(
        '/api/mobile/auth/facebook-login',
        body: {
          'facebookId': facebookId,
          'email': email,
          'firstName': firstName,
          'lastName': lastName,
          'avatarUrl': avatarUrl,
        },
      );

      final respData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respData['success'] == true) {
          final token = respData['token'] ?? respData['data']?['token'];
          if (token != null) {
            await ApiService.setAuthToken(token);
            PushNotificationService.registerTokenAfterLogin();
          }
          return null; // Success!
        }
      }
      return respData['message'] ?? 'Facebook login failed.';
    } catch (e) {
      debugPrint('Error in loginWithFacebook: $e');
      return 'An unexpected error occurred during Facebook login.';
    }
  }
}
