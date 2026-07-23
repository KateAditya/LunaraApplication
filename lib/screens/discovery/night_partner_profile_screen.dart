import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_profile_image.dart';

class NightPartnerProfileScreen extends StatefulWidget {
  final String partnerId;
  final Map<dynamic, dynamic> venue;
  final String date;
  final String time;

  const NightPartnerProfileScreen({
    super.key,
    required this.partnerId,
    required this.venue,
    required this.date,
    required this.time,
  });

  @override
  State<NightPartnerProfileScreen> createState() => _NightPartnerProfileScreenState();
}

class _NightPartnerProfileScreenState extends State<NightPartnerProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  bool _isRequested = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final res = await ApiService.fetchPartnerProfilePreview(widget.partnerId);
    if (mounted) {
      setState(() {
        _profile = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendRequest() async {
    final venueId = widget.venue['id']?.toString() ?? '';
    final res = await ApiService.sendNightPartnerRequest(
      partnerId: widget.partnerId,
      venueId: venueId,
      date: widget.date,
      time: widget.time,
    );

    if (!mounted) return;

    if (res != null) {
      setState(() => _isRequested = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Partner request sent to ${_profile?['firstName']}! 🎉'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send partner request.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = _profile?['firstName']?.toString() ?? 'User';
    final int? age = _profile?['age'] is int ? _profile!['age'] : null;
    final String photoUrl = _profile?['primaryPhoto']?.toString() ?? '';
    final bool isVerified = _profile?['isVerified'] == true;
    final String bio = _profile?['bio']?.toString() ?? 'Loves nightlife, music, and socializing!';
    final List interests = (_profile?['interests'] is List) ? _profile!['interests'] : ['Music', 'Parties', 'Socializing'];
    final String city = _profile?['city']?.toString() ?? 'Pune';
    final String occupation = _profile?['occupation']?.toString() ?? 'Professional';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          name.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'AllroundGothic',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Center Avatar Card
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  children: [
                                    LunaraProfileImage(
                                      userData: {'profilePhotoUrl': photoUrl.isNotEmpty ? photoUrl : null},
                                      radius: 60,
                                    ),
                                    if (isVerified)
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.verified,
                                            color: LunaraTheme.cyberCyan,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  age != null ? '$name, $age' : name,
                                  style: const TextStyle(
                                    fontFamily: 'AllroundGothic',
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$occupation • $city',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Bio Card
                          const Text(
                            'ABOUT',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Text(
                              bio,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Interests Section
                          const Text(
                            'INTERESTS',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: interests.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  tag.toString(),
                                  style: const TextStyle(
                                    color: LunaraTheme.electricViolet,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Trust Badge Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF3EEFF), Color(0xFFF8F4FF)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0x1A7F00FF)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.shield_outlined, color: LunaraTheme.electricViolet),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Verified Member',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Identity and profile validated by Lunara Trust Engine.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Send Request Bar
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isRequested ? null : _sendRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRequested ? Colors.grey[300] : LunaraTheme.electricViolet,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _isRequested ? 'REQUEST SENT' : 'SEND PARTNER REQUEST',
                          style: TextStyle(
                            color: _isRequested ? Colors.grey[600] : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
