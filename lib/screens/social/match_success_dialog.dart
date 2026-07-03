import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import 'chat_screen.dart';

class MatchSuccessDialog extends StatelessWidget {
  final Map<String, dynamic> matchedUser;

  const MatchSuccessDialog({super.key, required this.matchedUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTitle(),
              const SizedBox(height: 60),
              _buildAvatars(),
              const SizedBox(height: 60),
              _buildMessage(),
              const SizedBox(height: 48),
              _buildCTAs(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          "IT'S A",
          style: LunaraTheme.bodyStyle.copyWith(
            fontSize: 16,
            letterSpacing: 8,
            fontWeight: FontWeight.w100,
          ),
        ),
        Text(
          "LUNARA MATCH",
          style: LunaraTheme.headingStyle.copyWith(
            fontSize: 40,
            foreground: Paint()
              ..shader = LunaraTheme.primaryGradient.createShader(
                const Rect.fromLTWH(0.0, 0.0, 300.0, 70.0),
              ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatars() {
    return SizedBox(
      height: 180,
      width: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // User Avatar (Left - "You")
          Positioned(
            left: 20,
            child: _avatarCircle(
              LunaraTheme.logoIcon,
              LunaraTheme.primaryRich,
              isAsset: true,
            ),
          ),
          // Matched User Avatar (Right)
          Positioned(
            right: 20,
            child: _avatarCircle(
              matchedUser['image'],
              LunaraTheme.accentVivid,
              isAsset: matchedUser['isAsset'] == true,
            ),
          ),
          // Heart Icon in middle
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: LunaraTheme.primaryDeep,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(String url, Color borderColor, {bool isAsset = false}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 70,
        backgroundImage: isAsset
            ? AssetImage(url) as ImageProvider
            : NetworkImage(url),
      ),
    );
  }

  Widget _buildMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        "You and ${matchedUser['name']} have both liked each other. Start the conversation tonight!",
        textAlign: TextAlign.center,
        style: LunaraTheme.bodyStyle.copyWith(fontSize: 14, height: 1.5),
      ),
    );
  }

  Widget _buildCTAs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          LunaraActionButton(
            text: 'SEND A MESSAGE',
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    user: {
                      'name': matchedUser['name'] ?? 'User',
                      'image': matchedUser['image'] ?? '',
                      'isAsset': matchedUser['isAsset'] ?? false,
                      'online': true,
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CONTINUE DISCOVERING',
              style: LunaraTheme.bodyStyle.copyWith(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
