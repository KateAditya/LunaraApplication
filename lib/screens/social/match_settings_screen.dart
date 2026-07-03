import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';

class MatchSettingsScreen extends StatefulWidget {
  const MatchSettingsScreen({super.key});

  @override
  State<MatchSettingsScreen> createState() => _MatchSettingsScreenState();
}

class _MatchSettingsScreenState extends State<MatchSettingsScreen> {
  RangeValues _ageRange = const RangeValues(21, 35);
  double _distance = 10;
  final List<String> _selectedIntents = ['Socialize'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildSection(
                      'AGE RANGE',
                      '${_ageRange.start.toInt()} - ${_ageRange.end.toInt()}',
                    ),
                    RangeSlider(
                      values: _ageRange,
                      min: 18,
                      max: 60,
                      activeColor: LunaraTheme.accentVivid,
                      inactiveColor: Colors.white10,
                      onChanged: (values) => setState(() => _ageRange = values),
                    ),
                    const SizedBox(height: 32),
                    _buildSection('MAX DISTANCE', '${_distance.toInt()} KM'),
                    Slider(
                      value: _distance,
                      min: 1,
                      max: 50,
                      activeColor: LunaraTheme.primaryRich,
                      inactiveColor: Colors.white10,
                      onChanged: (value) => setState(() => _distance = value),
                    ),
                    const SizedBox(height: 32),
                    _buildSection('INTENT', ''),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        'Socialize',
                        'Party',
                        'Table Share',
                        'Networking',
                      ].map((intent) => _vibeChip(intent)).toList(),
                    ),
                    const SizedBox(height: 48),
                    _buildSwitch(
                      'INCOGNITO MODE',
                      'Hide your profile from non-matches.',
                    ),
                    _buildSwitch(
                      'SUPER-VIBE ONLY',
                      'Only see people with 90%+ match score.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'DISCOVERY SETTINGS',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: LunaraTheme.accentVivid,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vibeChip(String label) {
    bool isSelected = _selectedIntents.contains(label);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIntents.remove(label);
          } else {
            _selectedIntents.add(label);
          }
        });
      },
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        borderRadius: BorderRadius.circular(20),
        borderColor: isSelected ? LunaraTheme.accentVivid : Colors.white10,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? LunaraTheme.accentVivid : Colors.white54,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: true,
            onChanged: (v) {},
            activeTrackColor: LunaraTheme.accentVivid,
          ),
        ],
      ),
    );
  }
}
