import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import '../../services/onboarding_service.dart';
import 'profile_vibe_screen.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfileDetailsScreen({super.key, this.collectedData});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final _bioController = TextEditingController();

  // ── Nightlife Preferences ───────────────────────────────────────────────────
  final List<String> _nightlifeOptions = [
    'ROOFTOP LOUNGE',
    'PUBS',
    'CLUBS',
    'CAFES',
    'FINE DINING',
    'LIVE MUSIC',
    'DJ NIGHTS',
    'SPORTS SCREENING',
  ];
  final Set<String> _selectedNightlife = {};

  // ── Interests ───────────────────────────────────────────────────────────────
  final List<String> _interestOptions = [
    'TRAVEL',
    'FITNESS',
    'MOVIES',
    'MUSIC',
    'FOOD',
    'PHOTOGRAPHY',
    'GAMING',
    'BUSINESS',
    'STARTUPS',
    'ENTREPRENEURSHIP',
    'SPORTS',
    'READING',
    'DANCING',
    'ART',
    'FASHION',
    'PETS',
    'NATURE',
    'ADVENTURE',
  ];
  final Set<String> _selectedInterests = {};

  // ── Looking For ─────────────────────────────────────────────────────────────
  final List<String> _lookingForOptions = [
    'NEW FRIENDS',
    'SOCIAL OUTINGS',
    'ACTIVITY PARTNER',
    'NETWORKING',
    'EVENT COMPANIONS',
    'CASUAL MEETUPS',
    'MEANINGFUL CONNECTIONS',
  ];
  final Set<String> _selectedLookingFor = {};

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                _buildProgressBar(),
                const SizedBox(height: 32),
                Text(
                  'STEP 2 / 4',
                  style: LunaraTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: LunaraTheme.accentVivid,
                  ),
                ),
                Text(
                  'BIO & INTERESTS',
                  style: LunaraTheme.headingStyle.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 40),

                // ── Bio ───────────────────────────────────────────────────────
                _buildSectionLabel('YOUR STORY'),
                _buildBioInput(),
                const SizedBox(height: 40),

                // ── Nightlife Preferences ─────────────────────────────────────
                _buildSectionLabel('NIGHTLIFE PREFERENCE'),
                const SizedBox(height: 4),
                Text(
                  'What scenes match your energy?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTagSelector(_nightlifeOptions, _selectedNightlife),
                const SizedBox(height: 40),

                // ── Interests ─────────────────────────────────────────────────
                _buildSectionLabel('INTERESTS'),
                const SizedBox(height: 4),
                Text(
                  'What do you vibe with beyond the night?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTagSelector(_interestOptions, _selectedInterests),
                const SizedBox(height: 40),

                // ── Looking For ───────────────────────────────────────────────
                _buildSectionLabel('LOOKING FOR'),
                const SizedBox(height: 4),
                Text(
                  'What kind of connections are you seeking?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTagSelector(_lookingForOptions, _selectedLookingFor),
                const SizedBox(height: 80),

                LunaraActionButton(
                  text: 'CONTINUE',
                  onPressed: () async {
                    final data = widget.collectedData != null
                        ? Map<String, dynamic>.from(widget.collectedData!)
                        : <String, dynamic>{};

                    data['bio'] = _bioController.text.trim();
                    data['nightlifePreference'] = _selectedNightlife.toList();
                    data['interests'] = _selectedInterests.toList();
                    data['lookingFor'] = _selectedLookingFor.isNotEmpty
                        ? _selectedLookingFor.toList()
                        : <String>[];

                    await OnboardingService.saveProgress('profile_details', data);

                    if (!context.mounted) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfileVibeScreen(collectedData: data),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Builders ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
      onPressed: () => Navigator.pop(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: List.generate(4, (index) {
        final active = index <= 1;
        final current = index == 1;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 4,
            decoration: BoxDecoration(
              color: active
                  ? LunaraTheme.primaryRich
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
              boxShadow: current
                  ? [
                      BoxShadow(
                        color: LunaraTheme.primaryRich.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBioInput() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: TextField(
        controller: _bioController,
        maxLines: 4,
        maxLength: 200,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Tell the night about yourself...',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
          ),
          border: InputBorder.none,
          counterStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
          ),
        ),
      ),
    );
  }

  Widget _buildTagSelector(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: options.map((tag) {
        final isSelected = selected.contains(tag);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                selected.remove(tag);
              } else {
                selected.add(tag);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: isSelected
                  ? LunaraTheme.primaryRich.withValues(alpha: 0.18)
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
              border: Border.all(
                color: isSelected
                    ? LunaraTheme.primaryDeep
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check_circle, size: 13, color: LunaraTheme.accentVivid),
                  const SizedBox(width: 5),
                ],
                Text(
                  tag,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
