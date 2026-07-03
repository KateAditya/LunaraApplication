import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';

class AdvancedFiltersScreen extends StatefulWidget {
  const AdvancedFiltersScreen({super.key});

  @override
  State<AdvancedFiltersScreen> createState() => _AdvancedFiltersScreenState();
}

class _AdvancedFiltersScreenState extends State<AdvancedFiltersScreen> {
  final List<String> _vibes = [
    'TECHNO',
    'ROOFTOP',
    'CHILL',
    'COCKTAILS',
    'LIVE',
    'UNDERGROUND',
    'JAZZ',
    'HOUSE',
  ];
  final TextEditingController _searchController = TextEditingController();
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  final Set<String> _selectedVibes = {'TECHNO', 'ROOFTOP'};
  double _priceLevel = 2.0; // Default to 'medium'
  double _radius = 5.0;
  String? _selectedCrowdDensity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchBox(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('VIBE CATEGORIES'),
                    const SizedBox(height: 16),
                    _buildVibeTags(),
                    const SizedBox(height: 40),
                    _buildSectionLabel('PRICE LEVEL'),
                    const SizedBox(height: 16),
                    _buildPriceSelector(),
                    const SizedBox(height: 40),
                    _buildSectionLabel('SEARCH RADIUS (${_radius.toInt()} KM)'),
                    const SizedBox(height: 16),
                    _buildRadiusSlider(),
                    const SizedBox(height: 40),
                    _buildSectionLabel('CROWD DENSITY'),
                    const SizedBox(height: 16),
                    _buildCrowdDensitySelector(),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
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
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'VENUES FILTERS',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 2,
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedVibes.clear();
                _priceLevel = 2.0;
                _radius = 5.0;
                _selectedCrowdDensity = null;
              });
            },
            child: const Text(
              'RESET',
              style: TextStyle(color: Colors.deepPurple,fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search filters...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.grey),
          ),
        ),
        style: const TextStyle(color: Colors.black),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildVibeTags() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _vibes.map((vibe) {
        final isSelected = _selectedVibes.contains(vibe);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedVibes.remove(vibe);
              } else {
                _selectedVibes.add(vibe);
              }
            });
          },
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            borderRadius: BorderRadius.circular(30),
            borderColor: isSelected
                ? Colors.deepPurple
                : Colors.grey[400]!,
            opacity: isSelected ? 0.2 : 0.05,
            child: Text(
              vibe,
              style: TextStyle(
                color: isSelected
                    ? Colors.deepPurple
                    : Colors.black,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriceSelector() {
    final labels = ['lowest', 'low', 'medium', 'high', 'Very high'];
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.deepPurple,
            inactiveTrackColor: Colors.black12,
            thumbColor: Colors.black,
            overlayColor: Colors.deepPurple.withValues(alpha: 0.2),
            valueIndicatorShape: const RectangularSliderValueIndicatorShape(),
            valueIndicatorColor: Colors.deepPurple,
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: Slider(
            value: _priceLevel,
            min: 0,
            max: 4,
            divisions: 4,
            label: labels[_priceLevel.toInt()],
            onChanged: (v) => setState(() => _priceLevel = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (label) => Text(
                    label == 'Very high' ? 'V. HIGH' : label.toUpperCase(),
                    style: TextStyle(
                      color: labels.indexOf(label) == _priceLevel.toInt()
                          ? Colors.deepPurple
                          : Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRadiusSlider() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: Colors.deepPurple,
        inactiveTrackColor: Colors.black12,
        thumbColor: Colors.black,
        overlayColor: Colors.deepPurple.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: _radius,
        min: 1,
        max: 50,
        onChanged: (v) => setState(() => _radius = v),
      ),
    );
  }

  Widget _buildCrowdDensitySelector() {
    final types = [
      {'label': 'CHILL', 'icon': Icons.nightlight_outlined},
      {'label': 'LIVELY', 'icon': Icons.wb_sunny_outlined},
      {'label': 'PACKED', 'icon': Icons.flash_on_outlined},
    ];

    return Row(
      children: types.map((type) {
        final label = type['label'] as String;
        final isSelected = _selectedCrowdDensity == label;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCrowdDensity = isSelected ? null : label;
                });
              },
              child: GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                borderRadius: BorderRadius.circular(16), 
                borderColor: isSelected
                    ? Colors.deepPurple
                    : Colors.grey[400]!,
                child: Column(
                  children: [
                    Icon(
                      type['icon'] as IconData,
                      color: isSelected
                          ? Colors.deepPurple
                          : Colors.black,
                      size: 20,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.deepPurple : Colors.black,
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: LunaraActionButton(
        text: 'APPLY FILTERS',
        onPressed: () {
          Navigator.pop(context, {
            'vibes': _selectedVibes.toList(),
            'priceLevel': _priceLevel.toInt(),
            'radius': _radius,
            'crowdDensity': _selectedCrowdDensity,
          });
        },
      ),
    );
  }
}
