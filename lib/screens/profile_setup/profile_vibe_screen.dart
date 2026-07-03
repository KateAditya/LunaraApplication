import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import 'profile_privacy_screen.dart';

class ProfileVibeScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfileVibeScreen({super.key, this.collectedData});

  @override
  State<ProfileVibeScreen> createState() => _ProfileVibeScreenState();
}

class _ProfileVibeScreenState extends State<ProfileVibeScreen> {
  // ── Music Genres ────────────────────────────────────────────────────────────
  final List<String> _musicGenres = [
    'BOLLYWOOD',
    'PUNJABI',
    'SUFI',
    'LIVE BANDS',
    'MARATHI',
    'KONKANI',
    'HIP HOP',
    'JAZZ',
    'EDM',
    'INSTRUMENTAL',
    'R&B',
    'INDIE',
  ];
  final Set<String> _selectedGenres = {'BOLLYWOOD', 'PUNJABI'};

  String _smokingHabit = 'NON-SMOKER';
  String _drinkingHabit = 'SOCIALLY';
  final _educationController = TextEditingController();
  final _occupationController = TextEditingController();

  RangeValues _budgetRange = const RangeValues(2000, 10000);

  @override
  void dispose() {
    _educationController.dispose();
    _occupationController.dispose();
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
                  'STEP 3 / 4',
                  style: LunaraTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: LunaraTheme.accentVivid,
                  ),
                ),
                Text(
                  'MUSIC & BUDGET',
                  style: LunaraTheme.headingStyle.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 40),

                // ── Music Vibes ───────────────────────────────────────────────
                _buildInputLabel('MUSIC VIBES'),
                const SizedBox(height: 4),
                Text(
                  'Pick all that hit your soul',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                _buildMusicTags(),
                const SizedBox(height: 48),

                // ── Lifestyle ────────────────────────────────────────────────
                _buildInputLabel('LIFESTYLE HABITS'),
                const SizedBox(height: 12),
                _buildLifestyleSelector(
                  title: 'SMOKING',
                  options: ['NON-SMOKER', 'SOCIALLY', 'REGULARLY'],
                  currentValue: _smokingHabit,
                  onSelect: (val) => setState(() => _smokingHabit = val),
                  icon: Icons.smoking_rooms_outlined,
                ),
                const SizedBox(height: 16),
                _buildLifestyleSelector(
                  title: 'DRINKING',
                  options: ['NEVER', 'SOCIALLY', 'OFTEN'],
                  currentValue: _drinkingHabit,
                  onSelect: (val) => setState(() => _drinkingHabit = val),
                  icon: Icons.local_bar_outlined,
                ),
                const SizedBox(height: 48),

                // ── Professional Background ───────────────────────────────────
                _buildInputLabel('PROFESSIONAL BACKGROUND (Optional)'),
                _buildGlassInput(
                  controller: _occupationController,
                  hint: 'What do you do? (e.g., Designer)',
                  icon: Icons.work_outline,
                ),
                const SizedBox(height: 16),
                _buildGlassInput(
                  controller: _educationController,
                  hint: 'Where did you study?',
                  icon: Icons.school_outlined,
                ),
                const SizedBox(height: 48),

                // ── Budget Range ─────────────────────────────────────────────
                _buildInputLabel('BUDGET RANGE (PER NIGHT)'),
                _buildBudgetSlider(),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '₹${_budgetRange.start.round()} – ₹${_budgetRange.end.round()}+',
                    style: LunaraTheme.headingStyle.copyWith(
                      color: LunaraTheme.accentVivid,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 80),

                LunaraActionButton(
                  text: 'CONTINUE',
                  onPressed: () {
                    final data = widget.collectedData != null
                        ? Map<String, dynamic>.from(widget.collectedData!)
                        : <String, dynamic>{};

                    data['musicPreference'] = _selectedGenres.toList();
                    data['smokingPreference'] = _smokingHabit;
                    data['drinkPreference'] = [_drinkingHabit];
                    data['occupation'] = _occupationController.text.trim();
                    data['education'] = _educationController.text.trim();
                    data['budgetRange'] =
                        '${_budgetRange.start.round()}-${_budgetRange.end.round()}';

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfilePrivacyScreen(collectedData: data),
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
        final active = index <= 2;
        final current = index == 2;
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

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMusicTags() {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: _musicGenres.map((genre) {
        final isSelected = _selectedGenres.contains(genre);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedGenres.remove(genre);
              } else {
                _selectedGenres.add(genre);
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
                  Icon(Icons.music_note, size: 12, color: LunaraTheme.accentVivid),
                  const SizedBox(width: 4),
                ],
                Text(
                  genre,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
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

  Widget _buildBudgetSlider() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: LunaraTheme.accentVivid,
        inactiveTrackColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        thumbColor: Theme.of(context).colorScheme.onSurface,
        overlayColor: LunaraTheme.accentVivid.withValues(alpha: 0.2),
        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      ),
      child: RangeSlider(
        values: _budgetRange,
        min: 0,
        max: 50000,
        divisions: 50,
        labels: RangeLabels(
          '₹${_budgetRange.start.round()}',
          '₹${_budgetRange.end.round()}',
        ),
        onChanged: (values) {
          setState(() {
            _budgetRange = values;
          });
        },
      ),
    );
  }

  Widget _buildLifestyleSelector({
    required String title,
    required List<String> options,
    required String currentValue,
    required Function(String) onSelect,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.map((option) {
            final isSelected = currentValue == option;
            return GestureDetector(
              onTap: () => onSelect(option),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                borderRadius: BorderRadius.circular(20),
                borderColor: isSelected
                    ? LunaraTheme.accentVivid
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                opacity: isSelected ? 0.2 : 0.05,
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGlassInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      borderRadius: BorderRadius.circular(16),
      child: TextField(
        controller: controller,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
          ),
          border: InputBorder.none,
          icon: Icon(icon, color: LunaraTheme.primaryRich, size: 20),
        ),
      ),
    );
  }
}
