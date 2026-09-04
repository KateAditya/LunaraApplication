import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/optimistic_action_guard.dart';
import '../../widgets/lunara_profile_image.dart';
import 'night_partner_profile_screen.dart';

class NightPartnerDiscoveryScreen extends StatefulWidget {
  final Map<dynamic, dynamic> venue;
  final String date;
  final String time;

  const NightPartnerDiscoveryScreen({
    super.key,
    required this.venue,
    required this.date,
    required this.time,
  });

  @override
  State<NightPartnerDiscoveryScreen> createState() => _NightPartnerDiscoveryScreenState();
}

class _NightPartnerDiscoveryScreenState extends State<NightPartnerDiscoveryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _partners = [];
  final Set<String> _requestedUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadInterestedPartners();
  }

  Future<void> _loadInterestedPartners() async {
    setState(() => _isLoading = true);
    try {
      final venueId = widget.venue['id']?.toString() ?? '';
      final res = await ApiService.fetchInterestedPartners(
        venueId: venueId,
        date: widget.date,
      );
      if (mounted) {
        setState(() {
          _partners = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading interested partners: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendRequest(String partnerId, String name) async {
    if (_requestedUserIds.contains(partnerId)) return;
    if (!OptimisticActionGuard.start('PARTNER_REQ:$partnerId')) return;

    // Optimistic UI: immediately mark as requested
    setState(() {
      _requestedUserIds.add(partnerId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Partner request sent to $name! 🎉'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final venueId = widget.venue['id']?.toString() ?? '';
      final res = await ApiService.sendNightPartnerRequest(
        partnerId: partnerId,
        venueId: venueId,
        date: widget.date,
        time: widget.time,
      );

      if (res == null) {
        // Rollback
        if (mounted) {
          setState(() {
            _requestedUserIds.remove(partnerId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send partner request. Please try again.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _requestedUserIds.remove(partnerId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      OptimisticActionGuard.end('PARTNER_REQ:$partnerId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final venueName = widget.venue['name']?.toString() ?? 'Venue';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'INTERESTED PARTNERS',
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
                  const Icon(Icons.event_seat_rounded, color: LunaraTheme.electricViolet, size: 22),
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
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_partners.length} Interested',
                      style: const TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
                  : _partners.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadInterestedPartners,
                          color: LunaraTheme.electricViolet,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _partners.length,
                            itemBuilder: (context, index) {
                              final partner = _partners[index];
                              return _buildPartnerCard(partner);
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
                Icons.people_outline_rounded,
                size: 48,
                color: LunaraTheme.electricViolet,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Interested Partners Yet',
              style: TextStyle(
                fontFamily: 'AllroundGothic',
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your night is live! As soon as members mark themselves interested, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadInterestedPartners,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
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

  Widget _buildPartnerCard(Map<String, dynamic> partner) {
    final String partnerId = partner['userId']?.toString() ?? '';
    final String name = partner['firstName']?.toString() ?? 'User';
    final int? age = partner['age'] is int ? partner['age'] : null;
    final String photoUrl = partner['primaryPhoto']?.toString() ?? '';
    final bool isVerified = partner['isVerified'] == true;
    final double trustScore = (partner['trustScore'] as num?)?.toDouble() ?? 4.8;
    final int matchScore = (partner['compatibilityScore'] as num?)?.toInt() ?? 88;
    final bool hasRequested = _requestedUserIds.contains(partnerId);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
                // Profile Avatar with Verification Badge
                Stack(
                  children: [
                    LunaraProfileImage(
                      userData: {'profilePhotoUrl': photoUrl.isNotEmpty ? photoUrl : null},
                      radius: 32,
                    ),
                    if (LunaraTheme.getPlanBadgeColor(partner) != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.verified,
                            color: LunaraTheme.getPlanBadgeColor(partner),
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),

                // User Basic Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              age != null ? '$name, $age' : name,
                              style: const TextStyle(
                                fontFamily: 'AllroundGothic',
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              color: LunaraTheme.electricViolet,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            trustScore.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$matchScore% Match',
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NightPartnerProfileScreen(
                            partnerId: partnerId,
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                    onPressed: hasRequested ? null : () => _sendRequest(partnerId, name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasRequested ? Colors.grey[300] : LunaraTheme.electricViolet,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      hasRequested ? 'Requested' : 'Send Request',
                      style: TextStyle(
                        color: hasRequested ? Colors.grey[600] : Colors.white,
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
