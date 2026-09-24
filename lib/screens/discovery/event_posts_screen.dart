import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/night_partner_selector_sheet.dart';
import 'upcoming_party_screen.dart';
import '../../utils/lunara_date_formatter.dart';
import '../../widgets/lunara_cached_image.dart';

class EventPostsScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? initialEvents;

  const EventPostsScreen({super.key, this.initialEvents});

  @override
  State<EventPostsScreen> createState() => _EventPostsScreenState();
}

class _EventPostsScreenState extends State<EventPostsScreen> {
  List<Map<String, dynamic>> _eventPosts = [];
  bool _isLoading = true;
  final Set<String> _interestedEventIds = {};
  final Set<String> _togglingInterestIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialEvents != null && widget.initialEvents!.isNotEmpty) {
      _eventPosts = List<Map<String, dynamic>>.from(widget.initialEvents!);
      _isLoading = false;
      for (final p in _eventPosts) {
        if (p['isInterested'] == true) {
          _interestedEventIds.add(p['id']?.toString() ?? p['venueId']?.toString() ?? '');
        }
      }
    }
    _loadEventPosts();
  }

  Future<void> _loadEventPosts() async {
    if (_eventPosts.isEmpty) {
      setState(() => _isLoading = true);
    }
    List<Map<String, dynamic>> posts = await ApiService.fetchEventPosts();

    // Fallback to active party ads if event-posts endpoint is empty
    if (posts.isEmpty) {
      try {
        final dynamicPartyAds = await ApiService.fetchActiveAds(
          city: ApiService.selectedCity,
          type: 'Party',
        );
        if (dynamicPartyAds.isNotEmpty) {
          posts = dynamicPartyAds.map((ad) {
            final venue = ad['venue'] as Map<String, dynamic>? ?? {};
            final imageUrl = ad['imagePath'] != null
                ? (ad['imagePath'].toString().startsWith('http')
                      ? ad['imagePath'].toString()
                      : '${ApiService.baseUrl}${ad['imagePath']}')
                : '';

            String dateStr = ad['eventDate'] ?? ad['toDate'] ?? ad['fromDate'] ?? '';
            if (dateStr.isNotEmpty) {
              try {
                final dt = DateTime.parse(dateStr).toLocal();
                dateStr = DateFormat('EEEE, MMM dd').format(dt);
              } catch (_) {}
            } else {
              dateStr = 'Upcoming';
            }

            final bool isUnlimited = ad['isUnlimited'] == true;
            final int seatLimit = ad['seatLimit'] is num
                ? (ad['seatLimit'] as num).toInt()
                : (int.tryParse(ad['seatLimit']?.toString() ?? '0') ?? 0);
            final int filledSeats = ad['filledSeats'] is num
                ? (ad['filledSeats'] as num).toInt()
                : (int.tryParse(ad['filledSeats']?.toString() ?? '0') ?? 0);
            final int remainingSeats = isUnlimited ? 999999 : (seatLimit - filledSeats);
            final double entryPrice = ad['entryPrice'] is num
                ? (ad['entryPrice'] as num).toDouble()
                : (double.tryParse(ad['entryPrice']?.toString() ?? '0') ?? 0.0);

            final vName = venue['name'] ?? ad['venueName'] ?? ad['title'] ?? 'Venue';
            final loc = '${venue['area'] ?? venue['addressLine1'] ?? ad['area'] ?? ''}${venue['city'] != null ? ', ${venue['city']}' : (ad['city'] != null ? ', ${ad['city']}' : '')}'.trim();

            return {
              'id': ad['id'] != null ? 'ad_event_${ad['id']}' : 'party_${DateTime.now().millisecondsSinceEpoch}',
              'adId': ad['id'],
              'eventId': ad['id'],
              'upcomingNightId': ad['id'],
              'title': ad['title'] ?? ad['description'] ?? 'Special Event',
              'name': ad['title'] ?? ad['description'] ?? 'Special Event',
              'venue': vName,
              'venueName': vName,
              'date': dateStr,
              'rawDate': ad['eventDate'] ?? ad['toDate'] ?? ad['fromDate'],
              'time': LunaraDateFormatter.normalizeTimeTo12Hour(ad['time']?.toString() ?? '8:00 PM'),
              'location': loc,
              'aboutEvent': ad['aboutEvent'] ?? '',
              'image': imageUrl,
              'coverImageUrl': imageUrl,
              'interestedCount': ad['interestedCount'] ?? 0,
              'price': entryPrice > 0 ? entryPrice : null,
              'entryPrice': entryPrice > 0 ? entryPrice : null,
              'isUnlimited': isUnlimited,
              'seatLimit': seatLimit,
              'filledSeats': filledSeats,
              'remainingSeats': remainingSeats > 0 ? remainingSeats : 0,
              'venueId': ad['venueId'] ?? venue['id'],
              'venueMap': venue.isNotEmpty ? venue : null,
              'isInterested': ad['isInterested'] == true,
            };
          }).where((night) {
            if (night['rawDate'] != null) {
              try {
                final dt = DateTime.parse(night['rawDate'].toString()).toLocal();
                if (dt.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
                  return false;
                }
              } catch (_) {}
            }
            return true;
          }).toList();
        }
      } catch (e) {
        debugPrint('Fallback fetchActiveAds error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      if (posts.isNotEmpty) {
        _eventPosts = posts;
      } else if (widget.initialEvents != null && widget.initialEvents!.isNotEmpty) {
        _eventPosts = List<Map<String, dynamic>>.from(widget.initialEvents!);
      }
      _isLoading = false;
      for (final p in _eventPosts) {
        if (p['isInterested'] == true) {
          _interestedEventIds.add(p['id']?.toString() ?? p['venueId']?.toString() ?? '');
        }
      }
    });
  }

  Future<void> _toggleInterest(Map<String, dynamic> event) async {
    final eventKey = event['id']?.toString() ?? event['venueId']?.toString() ?? '';
    final venueId = event['venueId']?.toString() ?? event['id']?.toString() ?? event['adId']?.toString() ?? '';
    final date = event['rawDate']?.toString() ?? event['eventDate']?.toString() ?? event['date']?.toString() ?? '2026-09-06';

    if (venueId.isEmpty || _togglingInterestIds.contains(eventKey)) return;

    final isCurrentlyInterested = _interestedEventIds.contains(eventKey);

    // Optimistic UI update
    setState(() {
      if (isCurrentlyInterested) {
        _interestedEventIds.remove(eventKey);
        event['interestedCount'] = (event['interestedCount'] as int? ?? 1) - 1;
      } else {
        _interestedEventIds.add(eventKey);
        event['interestedCount'] = (event['interestedCount'] as int? ?? 0) + 1;
      }
      _togglingInterestIds.add(eventKey);
    });

    bool success = false;
    if (isCurrentlyInterested) {
      success = await ApiService.removeNightInterest(venueId: venueId, date: date);
    } else {
      success = await ApiService.markNightInterested(venueId: venueId, date: date);
    }

    if (!mounted) return;

    setState(() {
      _togglingInterestIds.remove(eventKey);
      if (!success) {
        // Revert on failure
        if (isCurrentlyInterested) {
          _interestedEventIds.add(eventKey);
          event['interestedCount'] = (event['interestedCount'] as int? ?? 0) + 1;
        } else {
          _interestedEventIds.remove(eventKey);
          event['interestedCount'] = (event['interestedCount'] as int? ?? 1) - 1;
        }
      }
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!isCurrentlyInterested ? 'Marked as Interested! 🎉' : 'Interest removed'),
          backgroundColor: !isCurrentlyInterested ? Colors.green : Colors.black87,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openInvitePartner(Map<String, dynamic> event) {
    final vName = event['venue']?.toString() ?? event['venueName']?.toString() ?? 'Venue';
    final flyer = event['image'] ?? event['coverImageUrl'] ?? event['imagePath'];
    final title = event['title'] ?? event['name'] ?? vName;
    NightPartnerSelectorSheet.show(
      context,
      party: event,
      venueId: event['venueId']?.toString() ?? '',
      venueName: vName,
      date: event['rawDate']?.toString() ?? '2026-09-06',
      time: LunaraDateFormatter.normalizeTimeTo12Hour(event['time']?.toString() ?? '8:00 PM'),
      bannerImage: flyer?.toString(),
      eventTitle: title?.toString(),
    );
  }

  void _openEventDetail(Map<String, dynamic> event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpcomingPartyScreen(
          party: event,
          venueMap: event['venueMap'] is Map ? Map<String, dynamic>.from(event['venueMap']) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F14) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'EVENT POSTS',
          style: TextStyle(
            fontFamily: 'AllroundGothic',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
          : _eventPosts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy_rounded, size: 54, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No upcoming event posts right now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back soon for new nightlife and event posts!',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: LunaraTheme.electricViolet,
                  onRefresh: _loadEventPosts,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _eventPosts.length,
                    itemBuilder: (context, index) {
                      final event = _eventPosts[index];
                      final eventKey = event['id']?.toString() ?? event['venueId']?.toString() ?? '';
                      final isInterested = _interestedEventIds.contains(eventKey);
                      final isToggling = _togglingInterestIds.contains(eventKey);
                      final title = event['title'] ?? 'Upcoming Night';
                      final venue = event['venue'] ?? event['venueName'] ?? 'Venue';
                      final date = event['date'] ?? 'Tonight';
                      final time = LunaraDateFormatter.normalizeTimeTo12Hour(event['time']?.toString() ?? '8:00 PM');
                      final location = event['location'] ?? '';
                      final about = event['aboutEvent'] ?? '';
                      final image = event['image'] ?? '';
                      final interestedCount = event['interestedCount'] ?? 0;
                      final price = event['price'];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E2A) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Event Banner Image with Date & Price Overlay
                              Stack(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: image.isNotEmpty
                                        ? LunaraCachedImage(
                                            image,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => Container(
                                              color: Colors.purple.shade900,
                                              child: const Center(child: Icon(Icons.nightlife, color: Colors.white, size: 40)),
                                            ),
                                          )
                                        : Container(
                                            color: Colors.purple.shade900,
                                            child: const Center(child: Icon(Icons.nightlife, color: Colors.white, size: 40)),
                                          ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.2),
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.8),
                                          ],
                                          stops: const [0.0, 0.4, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Date Pill
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        date.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Price Pill if available
                                  if (price != null)
                                    Positioned(
                                      top: 14,
                                      right: 14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: Text(
                                          '₹$price',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Title on Image
                                  Positioned(
                                    bottom: 12,
                                    left: 14,
                                    right: 14,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title.toUpperCase(),
                                          style: const TextStyle(
                                            fontFamily: 'AllroundGothic',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 1.0,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on_rounded, color: LunaraTheme.cyberCyan, size: 14),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '$venue • $time',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
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
                                ],
                              ),

                              // Content Info & Short Description
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (location.isNotEmpty) ...[
                                      Text(
                                        location,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? Colors.white54 : Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (about.isNotEmpty) ...[
                                      Text(
                                        about,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],

                                    // Interested Stats & Badges
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.people_alt_rounded, size: 14, color: LunaraTheme.electricViolet),
                                              const SizedBox(width: 5),
                                              Text(
                                                '$interestedCount Interested',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: LunaraTheme.electricViolet,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Action Buttons: [Interested] [Invite Partner] [View Event]
                                    Row(
                                      children: [
                                        // Interested Button
                                        Expanded(
                                          flex: 4,
                                          child: SizedBox(
                                            height: 42,
                                            child: OutlinedButton.icon(
                                              onPressed: isToggling ? null : () => _toggleInterest(event),
                                              icon: isToggling
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(strokeWidth: 2, color: LunaraTheme.electricViolet),
                                                    )
                                                  : Icon(
                                                      isInterested ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                                      size: 16,
                                                      color: LunaraTheme.electricViolet,
                                                    ),
                                              label: Text(
                                                isInterested ? 'INTERESTED' : 'INTERESTED',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: isInterested ? LunaraTheme.electricViolet : (isDark ? Colors.white : Colors.black87),
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                backgroundColor: isInterested ? LunaraTheme.electricViolet.withValues(alpha: 0.1) : Colors.transparent,
                                                side: BorderSide(
                                                  color: isInterested ? LunaraTheme.electricViolet : (isDark ? Colors.white24 : Colors.grey[300]!),
                                                ),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Invite Partner Button
                                        Expanded(
                                          flex: 4,
                                          child: SizedBox(
                                            height: 42,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _openInvitePartner(event),
                                              icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                                              label: const Text(
                                                'INVITE',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: LunaraTheme.electricViolet,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // View Event Detail Button
                                        InkWell(
                                          onTap: () => _openEventDetail(event),
                                          borderRadius: BorderRadius.circular(12),
                                          child: Container(
                                            height: 42,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[100],
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Center(
                                              child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: LunaraTheme.electricViolet),
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
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
