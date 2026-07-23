import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';
import 'night_partner_profile_screen.dart';

class NightInvitePartnerScreen extends StatefulWidget {
  final Map<dynamic, dynamic> venue;
  final String date;
  final String time;

  const NightInvitePartnerScreen({
    super.key,
    required this.venue,
    required this.date,
    required this.time,
  });

  @override
  State<NightInvitePartnerScreen> createState() => _NightInvitePartnerScreenState();
}

class _NightInvitePartnerScreenState extends State<NightInvitePartnerScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _invitees = [];
  final Set<String> _invitedUserIds = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAvailableInvitees();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _loadAvailableInvitees();
    });
  }

  Future<void> _loadAvailableInvitees() async {
    setState(() => _isLoading = true);
    try {
      final venueId = widget.venue['id']?.toString() ?? '';
      final res = await ApiService.fetchAvailableInvitees(
        venueId: venueId,
        date: widget.date,
        search: _searchController.text,
      );
      if (mounted) {
        setState(() {
          _invitees = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching available invitees: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendInvite(String partnerId, String name) async {
    final venueId = widget.venue['id']?.toString() ?? '';
    final res = await ApiService.sendNightPartnerRequest(
      partnerId: partnerId,
      venueId: venueId,
      date: widget.date,
      time: widget.time,
    );

    if (!mounted) return;

    if (res != null) {
      setState(() {
        _invitedUserIds.add(partnerId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation sent to $name! 🎉'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send invitation. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final venueName = widget.venue['name']?.toString() ?? 'Venue';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'INVITE A PARTNER',
          style: TextStyle(
            fontFamily: 'AllroundGothic',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 1.2,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Event Info Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read_rounded, color: LunaraTheme.electricViolet, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          venueName.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'AllroundGothic',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.date} • ${widget.time}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 13),
                        SizedBox(width: 4),
                        Text(
                          'No Conflicts',
                          style: TextStyle(
                            color: Color(0xFF15803D),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search members by name...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: LunaraTheme.electricViolet),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadAvailableInvitees();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
                  : _invitees.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadAvailableInvitees,
                          color: LunaraTheme.electricViolet,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _invitees.length,
                            itemBuilder: (context, index) {
                              final user = _invitees[index];
                              return _buildInviteeCard(user);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_search_rounded,
                size: 48,
                color: LunaraTheme.electricViolet,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Available Invitees Found',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No available members match "${_searchController.text}".'
                  : 'All eligible members currently have scheduled plans for this date.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                _searchController.clear();
                _loadAvailableInvitees();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh List'),
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.electricViolet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteeCard(Map<String, dynamic> user) {
    final String userId = user['userId']?.toString() ?? '';
    final String name = user['firstName']?.toString() ?? 'User';
    final int? age = user['age'] is int ? user['age'] : null;
    final String photoUrl = user['primaryPhoto']?.toString() ?? '';
    final bool isVerified = user['isVerified'] == true;
    final String occupation = user['occupation']?.toString() ?? 'Member';
    final String city = user['city']?.toString() ?? 'Pune';
    final bool hasPending = user['hasPendingInvite'] == true || _invitedUserIds.contains(userId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    LunaraProfileImage(
                      userData: {'profilePhotoUrl': photoUrl.isNotEmpty ? photoUrl : null},
                      radius: 28,
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
                            size: 16,
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
                        style: const TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$occupation • $city',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Available',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NightPartnerProfileScreen(
                            partnerId: userId,
                            venue: widget.venue,
                            date: widget.date,
                            time: widget.time,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: LunaraTheme.electricViolet),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'View Profile',
                      style: TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: hasPending ? null : () => _sendInvite(userId, name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasPending ? Colors.grey[300] : LunaraTheme.electricViolet,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      hasPending ? 'Invited' : 'Invite',
                      style: TextStyle(
                        color: hasPending ? Colors.grey[600] : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
