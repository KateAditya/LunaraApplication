import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  int _selectedFilter = 0; // 0: All, 1: Social, 2: Bookings, 3: System

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildFilters(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    _sectionHeader('TODAY'),
                    _notificationTile(
                      Icons.celebration,
                      'Elara Velvet',
                      'Exclusive guestlist invite for Platinum members',
                      '12:45 PM',
                      isUnread: true,
                    ),
                    _notificationTile(
                      Icons.person_add,
                      'Sarah J.',
                      'Sent you a direct message',
                      '10:30 AM',
                      isUnread: true,
                    ),
                    const SizedBox(height: 32),
                    _sectionHeader('YESTERDAY'),
                    _notificationTile(
                      Icons.payments,
                      'Payment Successful',
                      'Receipt for Table V1 @ Ultra Club',
                      'Oct 23, 11:20 PM',
                    ),
                    _notificationTile(
                      Icons.verified_user,
                      'Security Alert',
                      'New login detected from Mumbai, IN',
                      'Oct 23, 09:15 PM',
                    ),
                  ],
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'NOTIFICATIONS',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final filters = ['ALL', 'SOCIAL', 'BOOKINGS', 'SYSTEM'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: filters.asMap().entries.map((entry) {
          bool isSelected = _selectedFilter == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = entry.key),
            child: Column(
              children: [
                Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? LunaraTheme.accentVivid : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 20,
                  height: 2,
                  color: isSelected
                      ? LunaraTheme.accentVivid
                      : Colors.transparent,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _notificationTile(
    IconData icon,
    String title,
    String subtitle,
    String time, {
    bool isUnread = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        borderColor: isUnread
            ? LunaraTheme.accentVivid.withValues(alpha: 0.3)
            : Colors.white10,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isUnread ? LunaraTheme.accentVivid : Colors.white10)
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isUnread ? LunaraTheme.accentVivid : Colors.white54,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isUnread) ...[
              const SizedBox(width: 12),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: LunaraTheme.accentVivid,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
