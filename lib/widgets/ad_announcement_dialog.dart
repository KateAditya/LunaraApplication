import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/theme.dart';
import '../screens/discovery/venue_detail_screen.dart';
import '../screens/social/plan_hub_screen.dart';
import 'lunara_cached_image.dart';

class AdAnnouncementDialog extends StatefulWidget {
  final List<Map<String, dynamic>> ads;

  const AdAnnouncementDialog({super.key, required this.ads});

  static const int maxDailyShows = 2;
  static const String _prefKeyDate = 'live_party_announcement_last_date';
  static const String _prefKeyCount = 'live_party_announcement_daily_count';

  /// Check if the automatic app-start announcement can be shown today (max 2x/day)
  static Future<bool> shouldShowAutoPopup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final lastDate = prefs.getString(_prefKeyDate);
      int count = prefs.getInt(_prefKeyCount) ?? 0;

      if (lastDate != todayStr) {
        count = 0;
      }

      return count < maxDailyShows;
    } catch (_) {
      return true;
    }
  }

  /// Record that an announcement popup was displayed
  static Future<void> recordPopupShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final lastDate = prefs.getString(_prefKeyDate);
      int count = prefs.getInt(_prefKeyCount) ?? 0;

      if (lastDate != todayStr) {
        count = 0;
      }

      await prefs.setString(_prefKeyDate, todayStr);
      await prefs.setInt(_prefKeyCount, count + 1);
    } catch (_) {}
  }

  static Future<void> show(BuildContext context, Map<String, dynamic> ad) async {
    return showList(context, [ad], isAutomaticAppStart: false);
  }

  static Future<void> showList(
    BuildContext context,
    List<Map<String, dynamic>> adsList, {
    bool isAutomaticAppStart = false,
  }) async {
    final partyOnly = adsList.where((ad) {
      final adType = (ad['type'] ?? 'Party').toString();
      return adType == 'Party' || adType != 'Ads';
    }).toList();
    if (partyOnly.isEmpty) return;

    if (isAutomaticAppStart) {
      final canShow = await shouldShowAutoPopup();
      if (!canShow) return;
      await recordPopupShown();
    }

    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => AdAnnouncementDialog(ads: partyOnly),
    );
  }

  @override
  State<AdAnnouncementDialog> createState() => _AdAnnouncementDialogState();
}

class _AdAnnouncementDialogState extends State<AdAnnouncementDialog> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _calculateRemainingTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calculateRemainingTime();
    });
  }

  void _calculateRemainingTime() {
    if (widget.ads.isEmpty) return;
    final currentAd = widget.ads[_currentPage];
    try {
      final toDateStr = currentAd['toDate'] ?? currentAd['to_date'] ?? currentAd['rawDate'];
      if (toDateStr == null || toDateStr.toString().isEmpty) {
        if (mounted) {
          setState(() {
            _isExpired = false;
            _timeLeft = Duration.zero;
          });
        }
        return;
      }

      final targetDate = DateTime.parse(toDateStr.toString());
      final now = DateTime.now();
      final difference = targetDate.difference(now);

      if (difference.isNegative) {
        if (mounted) {
          setState(() {
            _isExpired = true;
            _timeLeft = Duration.zero;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isExpired = false;
            _timeLeft = difference;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _timeLeft = Duration.zero;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String _getImageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final cleanPath = path.replaceAll(r'\', '/');
    final baseUrl = ApiService.baseUrl;
    final formattedPath = cleanPath.startsWith('/') ? cleanPath : '/$cleanPath';
    return '$baseUrl$formattedPath';
  }

  Widget _buildTimeBox(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: LunaraTheme.electricViolet,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();

    final currentAd = widget.ads[_currentPage];
    final adType = (currentAd['type'] ?? 'Ads').toString();
    final isParty = adType == 'Party';
    final title = (currentAd['title'] ?? (isParty ? '🎉 Live Party Event!' : '📢 Special Offer')).toString();
    final city = currentAd['city']?.toString();
    final area = currentAd['area']?.toString();
    final venueName = currentAd['venue']?['name']?.toString() ?? currentAd['venueName']?.toString();
    final venueId = currentAd['venueId']?.toString() ?? currentAd['venue']?['id']?.toString();
    final aboutEvent = currentAd['aboutEvent']?.toString() ?? currentAd['about_event']?.toString();

    final days = _timeLeft.inDays.toString().padLeft(2, '0');
    final hours = (_timeLeft.inHours % 24).toString().padLeft(2, '0');
    final mins = (_timeLeft.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar with multi-ad pagination
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LunaraTheme.purpleGradient,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Icon(
                    isParty ? Icons.celebration_rounded : Icons.campaign_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isParty ? 'LIVE PARTY ANNOUNCEMENT' : 'SPECIAL ANNOUNCEMENT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.ads.length > 1) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_currentPage + 1}/${widget.ads.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            // Ad PageView Carousel
            SizedBox(
              height: widget.ads.length > 1 ? 190 : 180,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.ads.length,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                  _calculateRemainingTime();
                },
                itemBuilder: (ctx, index) {
                  final item = widget.ads[index];
                  final img = _getImageUrl(item['imagePath']?.toString() ?? item['image_path']?.toString() ?? item['image']?.toString());
                  if (img.isEmpty) {
                    return Container(
                      color: Colors.grey[100],
                      child: const Center(
                        child: Icon(Icons.campaign_rounded, size: 48, color: LunaraTheme.electricViolet),
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: LunaraCachedImage(
                          img,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey, size: 40),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Indicator Dots for Multi Ads
            if (widget.ads.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.ads.length, (idx) {
                  final isSel = idx == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: isSel ? 18 : 6,
                    decoration: BoxDecoration(
                      color: isSel ? LunaraTheme.electricViolet : Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],

            // Content body
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                  ),

                  if (venueName != null || city != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (venueName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.storefront_rounded, size: 12, color: LunaraTheme.electricViolet),
                                const SizedBox(width: 4),
                                Text(
                                  venueName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: LunaraTheme.electricViolet,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (city != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_rounded, size: 12, color: Colors.black54),
                                const SizedBox(width: 4),
                                Text(
                                  area != null ? '$area, $city' : city,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],

                  if (aboutEvent != null && aboutEvent.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      aboutEvent,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[700], height: 1.35),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Countdown Section
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer_rounded, size: 13, color: LunaraTheme.electricViolet),
                            const SizedBox(width: 5),
                            Text(
                              _isExpired ? 'OFFER / EVENT ENDED' : 'OFFER / EVENT ENDS IN',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isExpired) ...[
                          const Text(
                            'This party event or offer has expired.',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildTimeBox(days, 'Days'),
                              const Text(':', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LunaraTheme.electricViolet)),
                              _buildTimeBox(hours, 'Hours'),
                              const Text(':', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LunaraTheme.electricViolet)),
                              _buildTimeBox(mins, 'Mins'),
                              const Text(':', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LunaraTheme.electricViolet)),
                              _buildTimeBox(secs, 'Secs'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'DISMISS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LunaraTheme.purpleGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              if (venueId != null && venueId.isNotEmpty) {
                                final Map<String, dynamic> venueData = {};
                                if (currentAd['venue'] is Map) {
                                  venueData.addAll(Map<String, dynamic>.from(currentAd['venue']));
                                }
                                venueData['id'] = venueId;
                                if (venueName != null && venueData['name'] == null) venueData['name'] = venueName;
                                if (city != null && venueData['city'] == null) venueData['city'] = city;
                                if (area != null && venueData['area'] == null) venueData['area'] = area;

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => VenueDetailScreen(
                                      venue: venueData,
                                      initialPartyEvent: currentAd,
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const PlanHubScreen(),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  venueId != null ? 'EXPLORE VENUE' : 'VIEW PARTY HUB',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                              ],
                            ),
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
  }
}
