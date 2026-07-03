import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../social/chat_screen.dart';

class FriendsListScreen extends StatelessWidget {
  const FriendsListScreen({super.key});

  final List<Map<String, dynamic>> friends = const [
    {
      'name': 'Zane',
      'image': 'assets/images/profiles/zane.png',
      'status': 'Online',
    },
    {
      'name': 'Lyra',
      'image': 'assets/images/profiles/lyra.png',
      'status': 'Online',
    },
    {
      'name': 'Elara',
      'image': 'assets/images/profiles/elara.png',
      'status': 'Online',
    },
    {
      'name': 'Nova',
      'image': 'assets/images/profiles/elara.png',
      'status': 'Away',
    },
    {
      'name': 'Axel',
      'image': 'assets/images/profiles/zane.png',
      'status': 'Online',
    },
    {
      'name': 'Kael',
      'image': 'assets/images/profiles/zane.png',
      'status': 'Online',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(24.0),
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              user: {
                                'name': friend['name'],
                                'avatar': friend['image'],
                                'isAsset': true,
                              },
                            ),
                          ),
                        ),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          borderRadius: BorderRadius.circular(20),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundImage: AssetImage(friend['image']),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      friend['name'],
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: friend['status'] == 'Online'
                                                ? Colors.green
                                                : Colors.orange,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          friend['status'],
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.accentVivid.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline,
                                  color: LunaraTheme.accentVivid,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Text(
            'FRIENDS',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}
