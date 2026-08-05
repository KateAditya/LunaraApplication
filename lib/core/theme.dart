import 'package:flutter/material.dart';
class LunaraTheme {
  // --- Brand Colors ---
  static const Color electricViolet = Color(0xFF7F00FF);
  static const Color cyberCyan = Color(0xFF00E5FF);
  static const Color hotPink = Color(0xFFE100FF);
  static const Color deepBlue = Color(0xFF00A9FF);

  // Aliases for reversion compatibility
  static const Color primaryRich = electricViolet;
  static const Color accentVivid = cyberCyan;
  static const Color primaryDeep = hotPink;
  static const Color neutralSilver = deepBlue;
  static const Color midnightBlack = Color(0xFF0F0F12);
  static const Color obsidian = Color(0xFF0F0F12);
  static const Color darkSurface = Color(0xFF1A1A22);
  static const Color elevatedSurface = Color(0xFF24242E);
  static const Color lightBorder = Color(0xFFF0F0F0);
  static const Color nebulaGrey = Color(0xFF24242E);

  // Backgrounds & Surfaces
  static const Color darkBackground = Color(0xFF0F0F12);
  static const Color darkSurfaceLegacy = Color(0xFF1A1A22);

  // Gradients
  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [electricViolet, cyberCyan],
  );

  static const Gradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, Color(0xFFF8F9FF)], // Subtle blue-violet tint
  );

  static const Gradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [hotPink, electricViolet],
  );

  static const Gradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3e0f6b), Color(0xFFb952eb)],
  );

  static const Gradient deepPurpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3e0f6b), Color(0xFFb952eb)],
  );

  static const Gradient midnightGlow = primaryGradient;
  static const Gradient amberGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB800), Color(0xFFFF8A00)],
  );

  // --- Typography ---
  static const TextStyle headingStyle = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.black,
    letterSpacing: 0.5,
  );

  static const TextStyle subHeadingStyle = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 14,
    color: Colors.black87,
    height: 1.4,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.black54,
    letterSpacing: 1.2,
  );

  // --- Shadows ---
  static List<BoxShadow> get premiumShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 25,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get premiumCardShadow => [
        BoxShadow(
          color: electricViolet.withValues(alpha: 0.08),
          blurRadius: 25,
          offset: const Offset(0, 10),
        ),
      ];

  // --- Themes ---
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: electricViolet,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: electricViolet,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(
          color: Colors.black, 
          fontSize: 20, 
          fontWeight: FontWeight.bold,
          fontFamily: 'AllroundGothic',
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: electricViolet,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: electricViolet,
        brightness: Brightness.dark,
      ),
    );
  }

  // Assets
  static const String logoVerticalDark = 'assets/images/logo_vertical_dark.png';
  static const String logoVerticalLight = 'assets/images/logo_vertical_light.png';
  static const String logoIcon = 'assets/images/logo_icon.png';
  static const String logo = 'assets/images/logo.png';
  static const String defaultAvatar = 'assets/images/default_avatar.png';

  /// Returns verification tick color according to user's purchased subscription plan.
  /// Returns null if user has no purchased plan (i.e. FREE tier).
  static Color? getPlanBadgeColor(dynamic user) {
    if (user == null) return null;
    String tier = '';
    if (user is Map) {
      tier = (user['subscriptionTier'] ??
              user['tier'] ??
              user['packageTier'] ??
              user['planTier'] ??
              'FREE')
          .toString()
          .toUpperCase();
    } else {
      try {
        tier = (user.subscriptionTier ?? '').toString().toUpperCase();
      } catch (_) {}
    }

    if (tier.isEmpty || tier == 'FREE') {
      return null; // No purchased plan -> Do not show tick icon
    }

    switch (tier) {
      case 'CORE':
        return const Color(0xFF00A9FF); // Core Blue
      case 'PLUS':
        return const Color(0xFF7F00FF); // Plus Purple
      case 'PRO':
        return const Color(0xFFE100FF); // Pro Magenta/Pink
      case 'ELITE':
        return const Color(0xFFFFB703); // Elite Gold/Amber
      default:
        return const Color(0xFF00A9FF);
    }
  }
}
