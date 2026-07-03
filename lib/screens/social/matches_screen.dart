import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../home/dashboard.dart';
import 'post_detail_screen.dart';
import '../discovery/payment_confirmation_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Map<String, dynamic>>? _plans;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _plans = [];
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await ApiService.fetchPartyPlans();
      final filteredPlans = plans.where((plan) {
        final planDateTimeStr = plan['planDateTime'];
        if (planDateTimeStr == null) return false;
        try {
          final dt = DateTime.parse(planDateTimeStr).toLocal();
          return dt.isAfter(DateTime.now());
        } catch (_) {
          return true;
        }
      }).toList();

      if (mounted) {
        setState(() {
          _plans = filteredPlans;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dt = DateTime.parse(dateTimeStr).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return isToday ? 'Tonight at $timeStr' : '${dt.day}/${dt.month}/${dt.year} at $timeStr';
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _getElapsed(String? createdAtStr) {
    if (createdAtStr == null) return '';
    try {
      final dt = DateTime.parse(createdAtStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return '';
    }
  }

  Color _getMatchColor(int percentage) {
    if (percentage >= 90) return const Color(0xFFD500F9);
    if (percentage >= 80) return const Color(0xFFFFB800);
    if (percentage >= 70) return const Color(0xFFE6C200);
    return const Color(0xFF00B4D8);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Light background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black), // Dark icon
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const Dashboard()),
              (route) => false,
            );
          },
        ),
        title: const Text(
          'LIVE FEED',
          style: TextStyle(
            color: Colors.black, // Dark text
            fontWeight: FontWeight.bold,
            letterSpacing: 4.0,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black87), // Dark icon
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: LunaraTheme.deepBlue))
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // LIVE Header
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_plans?.length ?? 0} plans • ${_plans?.length ?? 0} updates tonight',
                      style: TextStyle(
                        color: Colors.grey[700], // Darker grey for light theme
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // PLANS NEAR YOU Header
                Row(
                  children: [
                    Text(
                      'PLANS NEAR YOU',
                      style: TextStyle(
                        color: Colors.black, // Darker grey
                        fontSize: 12,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.grey.withOpacity(0.2), // Lighter divider
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_plans == null || _plans!.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'No active plans nearby right now.\nCheck back later!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ),
                // List of Cards
                ...(_plans ?? []).map((plan) => _buildPlanCard(plan)).toList(),
                const SizedBox(height: 32), // Bottom padding
              ],
            ),
          ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final user = plan['user'] ?? {};
    final venue = plan['venue'] ?? {};
    
    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final displayName = name.isEmpty ? 'Anonymous' : name;
    
    final job = user['occupation']?.toString().isNotEmpty == true 
        ? user['occupation'] 
        : 'Lunara Member';
        
    final venueName = venue['name'] ?? 'Unknown Venue';
    
    final time = _formatTime(plan['planDateTime']);
    final elapsed = _getElapsed(plan['createdAt']);
    
    // Generate a consistent pseudo-random match percentage based on the plan ID
    final planId = plan['id']?.toString() ?? '';
    final matchPercentage = 60 + (planId.hashCode.abs() % 36);
    final matchColor = _getMatchColor(matchPercentage);
    
    final profileUrl = user['profilePhotoUrl'] != null && user['profilePhotoUrl'].toString().isNotEmpty
        ? '${ApiService.baseUrl}${user['profilePhotoUrl']}' 
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, // White card background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: matchColor.withOpacity(0.3), // Slightly softer border
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // Subtle premium shadow
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Profile info and Match Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: profileUrl != null 
                    ? NetworkImage(profileUrl) 
                    : const AssetImage(LunaraTheme.defaultAvatar) as ImageProvider,
                onBackgroundImageError: (exception, stackTrace) {}, // Handle broken images silently
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.black, // Dark text
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.work_outline, color: Colors.grey[600], size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            job,
                            style: TextStyle(
                              color: Colors.black, // Darker grey
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: matchColor.withOpacity(0.1), // Lighter badge background
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '$matchPercentage%',
                      style: TextStyle(
                        color: matchColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'MATCH',
                      style: TextStyle(
                        color: matchColor,
                        fontSize: 8,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Divider
          Divider(color: Colors.grey.withOpacity(0.1), height: 1), // Darker divider for light theme
          const SizedBox(height: 16),
          // Row 2: Location and Time
          Row(
            children: [
              const Icon(Icons.location_on, color: LunaraTheme.deepBlue, size: 16), // Use deepBlue for better contrast on white
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$venueName • $time',
                  style: TextStyle(
                    color: Colors.black, // Dark text
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                elapsed,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Row 3: Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final postMap = {
                      'id': plan['id'],
                      'firstName': user['firstName'] ?? 'Anonymous',
                      'lastName': user['lastName'] ?? '',
                      'venue': venueName,
                      'content': plan['message'] ?? 'Let\'s catch up!',
                      'time': elapsed,
                      'profilePhotoUrl': user['profilePhotoUrl'],
                      'planDateTime': plan['planDateTime'],
                    };
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: postMap,
                          venue: venue,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_search, size: 18),
                  label: const Text('SEE DETAILS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LunaraTheme.electricViolet, // deepBlue for better light theme contrast
                    side: BorderSide(color: LunaraTheme.electricViolet.withOpacity(0.5)),
                    backgroundColor: LunaraTheme.electricViolet.withOpacity(0.05),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LunaraTheme.purpleGradient,
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final bool isPaidByPartner = plan['paymentStatus'] == 'paid_by_partner' || plan['isPaidByPartner'] == true;
                      if (isPaidByPartner) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Payment already paid by partner! You can join directly.'),
                            backgroundColor: LunaraTheme.electricViolet,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PaymentConfirmationScreen(
                              venue: venue,
                              date: plan['planDateTime'] ?? plan['createdAt'] ?? 'Today',
                              package: 'Party Plan Safety Deposit',
                              totalPrice: '₹99',
                              showSplitBill: false,
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('JOIN'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.transparent, // Let gradient show through
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
