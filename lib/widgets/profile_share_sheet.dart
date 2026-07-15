import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';

class ProfileShareSheet extends StatelessWidget {
  final String profileId;
  final String name;
  final String? age;
  final String? city;
  final String? profilePhotoUrl;
  final bool isAsset;

  const ProfileShareSheet({
    super.key,
    required this.profileId,
    required this.name,
    this.age,
    this.city,
    this.profilePhotoUrl,
    this.isAsset = false,
  });

  static void show(
    BuildContext context, {
    required String profileId,
    required String name,
    String? age,
    String? city,
    String? profilePhotoUrl,
    bool isAsset = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ProfileShareSheet(
        profileId: profileId,
        name: name,
        age: age,
        city: city,
        profilePhotoUrl: profilePhotoUrl,
        isAsset: isAsset,
      ),
    );
  }

  String get _shareUrl => 'https://lunara.app/profile/$profileId';
  String get _shareText => 'Check out $name\'s profile on Lunara! $_shareUrl';

  Future<void> _shareToWhatsApp(BuildContext context) async {
    final whatsappUrl = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(_shareText)}');
    final webUrl = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}');
    
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl);
    } else if (await canLaunchUrl(webUrl)) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar(context, 'Could not open WhatsApp.', Colors.red);
    }
  }

  Future<void> _shareToEmail(BuildContext context) async {
    final emailUrl = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent("Check out $name on Lunara!")}&body=${Uri.encodeComponent(_shareText)}',
    );
    if (await canLaunchUrl(emailUrl)) {
      await launchUrl(emailUrl);
    } else {
      _showSnackbar(context, 'Could not open Email client.', Colors.red);
    }
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    _showSnackbar(context, 'Profile link copied to clipboard!', Colors.green);
    Navigator.pop(context);
  }

  Future<void> _shareNatively(BuildContext context) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        _shareText,
        subject: 'Check out $name on Lunara!',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      _showSnackbar(context, 'Could not share natively.', Colors.red);
    }
  }

  void _showSnackbar(BuildContext context, String message, Color bgColor) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    ImageProvider? imageProvider;
    if (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty) {
      if (isAsset || profilePhotoUrl!.startsWith('assets/')) {
        imageProvider = AssetImage(profilePhotoUrl!);
      } else {
        imageProvider = NetworkImage(profilePhotoUrl!);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? LunaraTheme.midnightBlack : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            'SHARE PROFILE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 24),

          // Card Preview of the Profile
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: isDark ? null : LunaraTheme.cardGradient,
              color: isDark ? LunaraTheme.elevatedSurface : null,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                width: 1.5,
              ),
              boxShadow: isDark ? [] : LunaraTheme.premiumCardShadow,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: imageProvider,
                  backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  child: imageProvider == null
                      ? const Icon(Icons.person, size: 32, color: LunaraTheme.electricViolet)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        age != null ? '$name, $age' : name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (city != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: LunaraTheme.electricViolet,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              city!,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'LUNARA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: LunaraTheme.electricViolet,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Options Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildShareOption(
                context,
                icon: Icons.link_rounded,
                label: 'Copy Link',
                color: const Color(0xFF00C853),
                onTap: () => _copyToClipboard(context),
              ),
              _buildShareOption(
                context,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => _shareToWhatsApp(context),
              ),
              _buildShareOption(
                context,
                icon: Icons.alternate_email_rounded,
                label: 'Email',
                color: const Color(0xFF007AFF),
                onTap: () => _shareToEmail(context),
              ),
              _buildShareOption(
                context,
                icon: Icons.more_horiz_rounded,
                label: 'More',
                color: const Color(0xFFE040FB),
                onTap: () => _shareNatively(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
