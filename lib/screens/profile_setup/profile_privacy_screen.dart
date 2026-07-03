import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';
import 'profile_final_review_screen.dart';

class ProfilePrivacyScreen extends StatefulWidget {
  final Map<String, dynamic>? collectedData;
  const ProfilePrivacyScreen({super.key, this.collectedData});

  @override
  State<ProfilePrivacyScreen> createState() => _ProfilePrivacyScreenState();
}

class _ProfilePrivacyScreenState extends State<ProfilePrivacyScreen> {
  bool _invisibleMode = false;
  bool _matchingRadius = true;
  bool _bookingPermissions = true;

  final Set<String> _preferredGenders = {'ALL'};
  RangeValues _ageRange = const RangeValues(21, 35);

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
                  'STEP 4 / 4',
                  style: LunaraTheme.bodyStyle.copyWith(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: LunaraTheme.accentVivid,
                  ),
                ),
                Text(
                  'PRIVACY SETTINGS',
                  style: LunaraTheme.headingStyle.copyWith(fontSize: 32),
                ),
                const SizedBox(height: 40),
                _buildInputLabel('MATCHING PREFERENCES'),
                const SizedBox(height: 12),
                _buildGenderPreferences(),
                const SizedBox(height: 32),
                _buildInputLabel('AGE PREFERENCE'),
                _buildAgeSlider(),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '${_ageRange.start.round()} - ${_ageRange.end.round() == 60 ? '60+' : _ageRange.end.round()}',
                    style: LunaraTheme.headingStyle.copyWith(
                      color: LunaraTheme.accentVivid,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                _buildInputLabel('ACCOUNT PRIVACY'),
                const SizedBox(height: 12),
                _buildToggleCard(
                  'INVISIBLE MODE',
                  'Hide your profile from public discovery.',
                  _invisibleMode,
                  (v) => setState(() => _invisibleMode = v),
                ),
                const SizedBox(height: 16),
                _buildToggleCard(
                  'MATCHING RADIUS',
                  'Only show profiles within 10km of your location.',
                  _matchingRadius,
                  (v) => setState(() => _matchingRadius = v),
                ),
                const SizedBox(height: 16),
                _buildToggleCard(
                  'BOOKING ALERTS',
                  'Notify friends when you reserve a table.',
                  _bookingPermissions,
                  (v) => setState(() => _bookingPermissions = v),
                ),
                const SizedBox(height: 60),
                LunaraActionButton(
                  text: 'FINAL REVIEW',
                  onPressed: () {
                    final data = widget.collectedData != null
                        ? Map<String, dynamic>.from(widget.collectedData!)
                        : <String, dynamic>{};

                    data['preferredGenders'] = _preferredGenders.toList();
                    // We only have minAge in RegisterBasic, but user refining here:
                    data['minAgePreference'] = _ageRange.start.round();
                    data['maxAgePreference'] = _ageRange.end.round();
                    data['showMeInMatching'] = !_invisibleMode;
                    data['matchDistanceKm'] = _matchingRadius ? 10 : 100;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfileFinalReviewScreen(collectedData: data),
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
        final active = index <= 3;
        final current = index == 3;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 4,
            decoration: BoxDecoration(
              color: active ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
              boxShadow: current
                  ? [
                      BoxShadow(
                        color: LunaraTheme.primaryRich.withValues(
                          alpha: 0.5,
                        ),
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

  Widget _buildToggleCard(
    String title,
    String desc,
    bool value,
    Function(bool) onChanged,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LunaraTheme.headingStyle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: LunaraTheme.accentVivid,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGenderPreferences() {
    return Row(
      children: [
        _genderCard('MEN', _preferredGenders.contains('MEN')),
        const SizedBox(width: 8),
        _genderCard('WOMEN', _preferredGenders.contains('WOMEN')),
        const SizedBox(width: 8),
        _genderCard('ALL', _preferredGenders.contains('ALL')),
      ],
    );
  }

  Widget _genderCard(String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _preferredGenders.clear();
            _preferredGenders.add(label);
          });
        },
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          borderRadius: BorderRadius.circular(16),
          borderColor: isSelected ? LunaraTheme.primaryRich : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          opacity: isSelected ? 0.2 : 0.05,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.24),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgeSlider() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: LunaraTheme.accentVivid,
        inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        thumbColor: Theme.of(context).colorScheme.onSurface,
        overlayColor: LunaraTheme.accentVivid.withValues(alpha: 0.2),
        rangeThumbShape: const RoundRangeSliderThumbShape(
          enabledThumbRadius: 10,
        ),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      ),
      child: RangeSlider(
        values: _ageRange,
        min: 18,
        max: 60,
        divisions: 42,
        onChanged: (values) {
          setState(() {
            _ageRange = values;
          });
        },
      ),
    );
  }
}
