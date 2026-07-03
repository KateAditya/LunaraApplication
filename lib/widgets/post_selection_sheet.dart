import 'package:flutter/material.dart';
import '../core/theme.dart';

class PostSelectionSheet extends StatelessWidget {
  const PostSelectionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CREATE NEW',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, letterSpacing: 1),
          ),
          const SizedBox(height: 24),
          _buildOption(
            context,
            icon: Icons.event,
            title: 'Create a Plan',
            subtitle: 'Find a partner for a venue',
            color: LunaraTheme.electricViolet,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          _buildOption(
            context,
            icon: Icons.local_activity,
            title: 'Post an Event',
            subtitle: 'Share a party or gathering',
            color: LunaraTheme.hotPink,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          _buildOption(
            context,
            icon: Icons.send,
            title: 'Personal Invite',
            subtitle: 'Invite someone directly',
            color: LunaraTheme.cyberCyan,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black)),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
