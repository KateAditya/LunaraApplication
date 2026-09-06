import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/lunara_profile_image.dart';

class NightPartnerSelectorSheet extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String date;
  final String? time;

  const NightPartnerSelectorSheet({
    super.key,
    required this.venueId,
    required this.venueName,
    required this.date,
    this.time,
  });

  static Future<void> show(
    BuildContext context, {
    required String venueId,
    required String venueName,
    required String date,
    String? time,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NightPartnerSelectorSheet(
        venueId: venueId,
        venueName: venueName,
        date: date,
        time: time,
      ),
    );
  }

  @override
  State<NightPartnerSelectorSheet> createState() => _NightPartnerSelectorSheetState();
}

class _NightPartnerSelectorSheetState extends State<NightPartnerSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _invitees = [];
  bool _isLoading = true;
  final Set<String> _sentInviteUserIds = {};
  final Set<String> _loadingUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadInvitees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitees([String? query]) async {
    setState(() => _isLoading = true);
    final results = await ApiService.fetchAvailableInvitees(
      venueId: widget.venueId,
      date: widget.date,
      search: query,
    );
    if (!mounted) return;
    setState(() {
      _invitees = results;
      _isLoading = false;
      for (final item in _invitees) {
        if (item['hasPendingInvite'] == true) {
          _sentInviteUserIds.add(item['userId']?.toString() ?? '');
        }
      }
    });
  }

  Future<void> _sendInvite(Map<String, dynamic> partner) async {
    final partnerId = partner['userId']?.toString();
    if (partnerId == null || partnerId.isEmpty) return;

    if (_sentInviteUserIds.contains(partnerId)) return;

    setState(() {
      _loadingUserIds.add(partnerId);
    });

    final res = await ApiService.sendNightPartnerRequest(
      partnerId: partnerId,
      venueId: widget.venueId,
      date: widget.date,
      time: widget.time ?? '20:00',
    );

    if (!mounted) return;

    setState(() {
      _loadingUserIds.remove(partnerId);
      if (res != null) {
        _sentInviteUserIds.add(partnerId);
      }
    });

    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Invite sent to ${partner['firstName'] ?? 'partner'}! 🎉',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send invite. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161622) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INVITE A PARTNER',
                        style: TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.venueName} • ${widget.date}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey[300]!,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => _loadInvitees(val),
                decoration: InputDecoration(
                  hintText: 'Search people to invite...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  icon: const Icon(Icons.search, color: LunaraTheme.electricViolet, size: 20),
                  border: InputBorder.none,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadInvitees();
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // List of available partners
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                  )
                : _invitees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No available users found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try searching for another name or check back soon.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        itemCount: _invitees.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          final partner = _invitees[index];
                          final partnerId = partner['userId']?.toString() ?? '';
                          final isSent = _sentInviteUserIds.contains(partnerId);
                          final isInviting = _loadingUserIds.contains(partnerId);
                          final name = partner['firstName'] ?? 'User';
                          final age = partner['age'];
                          final city = partner['city'] ?? '';
                          final photo = partner['primaryPhoto'];
                          final score = partner['compatibilityScore'] ?? 88;
                          final isVerified = partner['isVerified'] == true;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    LunaraProfileImage(
                                      userData: {'profilePhotoUrl': photo},
                                      radius: 26,
                                    ),
                                    if (isVerified)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.verified,
                                            color: LunaraTheme.cyberCyan,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        age != null ? '$name, $age' : name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          if (city.isNotEmpty) ...[
                                            Text(
                                              city,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.white54 : Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(
                                            '$score% Vibe',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 38,
                                  child: ElevatedButton(
                                    onPressed: (isSent || isInviting)
                                        ? null
                                        : () => _sendInvite(partner),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isSent
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : LunaraTheme.electricViolet,
                                      foregroundColor: isSent ? Colors.green : Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: isSent
                                            ? const BorderSide(color: Colors.green, width: 1.2)
                                            : BorderSide.none,
                                      ),
                                    ),
                                    child: isInviting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            isSent ? 'INVITED ✓' : 'INVITE',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              letterSpacing: 0.8,
                                              color: isSent ? Colors.green : Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
