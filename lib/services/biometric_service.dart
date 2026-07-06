import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Checks if the device has biometric hardware and is enrolled.
  static Future<bool> isBiometricsAvailable() async {
    // Biometrics don't run on the web emulator natively like this, 
    // so we return true for testing purposes if on Web.
    if (kIsWeb) return true;
    
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Error checking biometrics: $e');
      return false;
    }
  }

  /// Triggers the native FaceID / TouchID popup.
  static Future<bool> authenticate({String reason = 'Please authenticate to log in'}) async {
    if (kIsWeb) {
      debugPrint('Biometrics bypassed on Web for testing.');
      return true;
    }

    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false, // allows fallback to device PIN/Pattern
        persistAcrossBackgrounding: true, // Keeps the UI open if app goes to background temporarily
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('Error using biometrics: $e');
      return false;
    }
  }
}
