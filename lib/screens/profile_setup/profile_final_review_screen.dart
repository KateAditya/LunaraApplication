import '../../services/auth_service.dart';
import '../../services/onboarding_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/glass_card.dart';
import '../home/dashboard.dart';

class ProfileFinalReviewScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfileFinalReviewScreen({super.key, this.collectedData});

  @override
  State<ProfileFinalReviewScreen> createState() =>
      _ProfileFinalReviewScreenState();
}

class _ProfileFinalReviewScreenState extends State<ProfileFinalReviewScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _scoreAnim;
  late Animation<double> _scoreProgress;

  @override
  void initState() {
    super.initState();
    final score = _calcReliabilityScore() / 100.0;
    _scoreAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scoreProgress = Tween<double>(begin: 0, end: score).animate(
      CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOutCubic),
    );
    // Kick off animation after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scoreAnim.forward();
    });
  }

  @override
  void dispose() {
    _scoreAnim.dispose();
    super.dispose();
  }

  /// Computes a profile completeness score (0–100) from filled fields.
  int _calcReliabilityScore() {
    final d = widget.collectedData ?? {};
    int pts = 0;

    // Photos (25 pts)
    final photos = d['photos'];
    final photoCount = (photos is List) ? photos.length : 0;
    if (photoCount >= 1) pts += 10;
    if (photoCount >= 2) pts += 10;
    if (d['selfieVerified'] == true) pts += 5;

    // Bio (10 pts)
    final bio = (d['bio'] as String?)?.trim() ?? '';
    if (bio.isNotEmpty) pts += 10;

    // Interests & Nightlife (15 pts)
    final interests = d['interests'];
    if (interests is List && interests.isNotEmpty) pts += 8;
    final nightlife = d['nightlifePreference'];
    if (nightlife is List && nightlife.isNotEmpty) pts += 7;

    // Looking For (10 pts)
    final lookingFor = d['lookingFor'];
    if (lookingFor is List && lookingFor.isNotEmpty) pts += 10;

    // Music (10 pts)
    final music = d['musicPreference'];
    if (music is List && music.isNotEmpty) pts += 10;

    // Lifestyle (10 pts)
    if ((d['smokingPreference'] as String?)?.isNotEmpty == true) pts += 5;
    if ((d['drinkPreference']) != null) pts += 5;

    // Professional & Location (10 pts)
    if ((d['occupation'] as String?)?.isNotEmpty == true) pts += 5;
    if ((d['city'] as String?)?.isNotEmpty == true || (d['education'] as String?)?.isNotEmpty == true) pts += 5;

    // Budget (5 pts)
    if ((d['budgetRange'] as String?)?.isNotEmpty == true) pts += 5;

    // Privacy / preferences (5 pts)
    if (d['preferredGenders'] != null) pts += 5;

    return pts.clamp(0, 100);
  }

  Future<void> _submitProfile() async {
    setState(() => _isLoading = true);

    final flatData = <String, dynamic>{};
    List<String> photosToUpload = [];

    if (widget.collectedData != null) {
      widget.collectedData!.forEach((key, value) {
        if (key == 'photos' && value is List) {
          photosToUpload = value.cast<String>();
        } else if (key == 'profile' || key == 'preferences') {
          if (value is Map) {
            value.forEach((k, v) => flatData[k.toString()] = v);
          }
        } else if (key != 'selfieVerified') {
          flatData[key.toString()] = value;
        }
      });
    }

    bool success = true;

    if (photosToUpload.isNotEmpty) {
      final photosUploaded = await AuthService.uploadPhotos(photosToUpload);
      if (!photosUploaded) {
        success = false;
        debugPrint('Failed to upload photos');
      }
    }

    if (success) {
      success = await AuthService.setupProfile(flatData);
    }

    setState(() => _isLoading = false);

    if (success && mounted) {
      await OnboardingService.clearProgress();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const Dashboard()),
        (route) => false,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = _calcReliabilityScore();

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                _buildSuccessRing(),
                const SizedBox(height: 36),
                Text(
                  'EVERYTHING IS SET',
                  style: LunaraTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    letterSpacing: 4,
                    color: LunaraTheme.accentVivid,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "YOU'RE READY",
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 32,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your nightlife profile is calibrated for maximum vibe.\nTime to explore the city.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 40),

                // ── Reliability Score Card ────────────────────────────────────
                _buildReliabilityCard(score),
                const SizedBox(height: 56),

                _isLoading
                    ? const CircularProgressIndicator(color: LunaraTheme.accentVivid)
                    : LunaraActionButton(
                        text: 'ENTER THE NIGHT',
                        onPressed: _submitProfile,
                      ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReliabilityCard(int score) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: LunaraTheme.accentVivid.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_outlined, color: LunaraTheme.accentVivid, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'USER RELIABILITY SCORE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scoreProgress,
                    builder: (context, _) {
                      final current = (_scoreProgress.value * 100).round();
                      return Text(
                        '$current / 100',
                        style: LunaraTheme.headingStyle.copyWith(
                          fontSize: 22,
                          color: _scoreColor(current),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Animated score bar
          AnimatedBuilder(
            animation: _scoreProgress,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _scoreProgress.value,
                      minHeight: 8,
                      backgroundColor:
                          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _scoreColor((_scoreProgress.value * 100).round()),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Breakdown rows
          _buildScoreRow(
            icon: Icons.person_outline,
            label: 'Profile Completeness',
            value: '${_calcCompleteness()}%',
            active: _calcCompleteness() > 0,
          ),
          const SizedBox(height: 12),
          _buildScoreRow(
            icon: Icons.verified_user_outlined,
            label: 'Selfie Verified',
            value: widget.collectedData?['selfieVerified'] == true ? 'Yes' : 'No',
            active: widget.collectedData?['selfieVerified'] == true,
          ),
          const SizedBox(height: 12),
          _buildScoreRow(
            icon: Icons.event_available_outlined,
            label: 'Meetup Activity',
            value: 'Pending',
            active: false,
            subtitle: 'Increases as you attend events',
          ),
          const SizedBox(height: 20),

          // Hint to improve score
          if (score < 80)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: LunaraTheme.accentVivid.withValues(alpha: 0.07),
                border: Border.all(
                  color: LunaraTheme.accentVivid.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 14, color: LunaraTheme.accentVivid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete your occupation, bio & interests to boost your score.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreRow({
    required IconData icon,
    required String label,
    required String value,
    required bool active,
    String? subtitle,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: active
              ? LunaraTheme.accentVivid
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active
                ? LunaraTheme.accentVivid
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  Color _scoreColor(int score) {
    if (score >= 75) return const Color(0xFF4CAF50);
    if (score >= 50) return LunaraTheme.accentVivid;
    return LunaraTheme.primaryDeep;
  }

  int _calcCompleteness() {
    final d = widget.collectedData ?? {};
    int filled = 0;
    const int total = 8;

    final photos = d['photos'];
    if (photos is List && photos.isNotEmpty) filled++;
    if ((d['bio'] as String?)?.isNotEmpty == true) filled++;
    if ((d['interests'] as List?)?.isNotEmpty == true) filled++;
    if ((d['nightlifePreference'] as List?)?.isNotEmpty == true) filled++;
    if ((d['lookingFor'] as List?)?.isNotEmpty == true) filled++;
    if ((d['musicPreference'] as List?)?.isNotEmpty == true) filled++;
    if ((d['occupation'] as String?)?.isNotEmpty == true) filled++;
    if ((d['education'] as String?)?.isNotEmpty == true) filled++;

    return ((filled / total) * 100).round();
  }

  Widget _buildSuccessRing() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: LunaraTheme.primaryRich.withValues(alpha: 0.2),
                blurRadius: 50,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
        // Ring
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: LunaraTheme.primaryRich, width: 2),
            gradient: const SweepGradient(
              colors: [
                LunaraTheme.primaryRich,
                LunaraTheme.accentVivid,
                LunaraTheme.primaryRich,
              ],
            ),
          ),
          child: Icon(
            Icons.verified_user_outlined,
            color: Theme.of(context).colorScheme.onSurface,
            size: 50,
          ),
        ),
      ],
    );
  }
}
