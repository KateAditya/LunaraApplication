import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';

class RateVenueScreen extends StatefulWidget {
  const RateVenueScreen({super.key});

  @override
  State<RateVenueScreen> createState() => _RateVenueScreenState();
}

class _RateVenueScreenState extends State<RateVenueScreen> {
  int _starRating = 0;
  final Set<String> _selectedTags = {};
  final TextEditingController _reviewController = TextEditingController();

  final List<String> _sentimentTags = [
    'Great DJ',
    'Chill Vibes',
    'Crowded',
    'Good Service',
    'Loud',
    'Premium Feel',
    'Fun Crowd',
    'Overpriced',
    'Clean',
    'Friendly Staff',
  ];

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVenueHeader(),
                    const SizedBox(height: 32),
                    _buildStarRating(),
                    const SizedBox(height: 32),
                    _buildSentimentTags(),
                    const SizedBox(height: 32),
                    _buildPhotoUpload(),
                    const SizedBox(height: 24),
                    _buildReviewField(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
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
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'RATE VENUE',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildVenueHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              image: const DecorationImage(
                image: NetworkImage('https://picsum.photos/seed/15/600/400'),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(20),
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ELARA VELVET',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'SAT, FEB 22 • VIP V1 • 6 Guests',
                    style: TextStyle(
                      color: LunaraTheme.electricViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating() {
    return Column(
      children: [
        const Center(
          child: Text(
            'HOW WAS YOUR NIGHT?',
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FittedBox(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final isSelected = index < _starRating;
                return GestureDetector(
                  onTap: () => setState(() => _starRating = index + 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Icon(
                      isSelected
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 42,
                      color: isSelected
                          ? LunaraTheme.electricViolet
                          : Colors.grey[200],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        if (_starRating > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Text(
                _ratingLabel,
                style: const TextStyle(
                  color: LunaraTheme.electricViolet,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _ratingLabel => switch (_starRating) {
    1 => 'TERRIBLE',
    2 => 'NOT GREAT',
    3 => 'DECENT',
    4 => 'AMAZING',
    5 => 'LEGENDARY',
    _ => '',
  };

  Widget _buildSentimentTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WHAT STOOD OUT?',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _sentimentTags.map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedTags.remove(tag);
                  } else {
                    _selectedTags.add(tag);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? LunaraTheme.electricViolet.withValues(alpha: 0.3)
                        : Colors.grey[100]!,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: isSelected
                        ? LunaraTheme.electricViolet
                        : Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPhotoUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REAL VIBE PHOTO',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Camera / Gallery picker would open here'),
                backgroundColor: LunaraTheme.electricViolet,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey[100]!,
                style: BorderStyle.solid,
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: LunaraTheme.electricViolet,
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'TAP TO ADD PHOTO',
                    style: TextStyle(
                      color: LunaraTheme.electricViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WRITE A REVIEW (OPTIONAL)',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: TextField(
            controller: _reviewController,
            maxLines: 4,
            style: const TextStyle(color: Colors.black, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tell others about your experience...',
              hintStyle: const TextStyle(color: Colors.black),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return LunaraActionButton(
      text: 'SUBMIT REVIEW',
      icon: Icons.send_rounded,
      onPressed: () {
        if (_starRating == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please select a star rating first'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return;
        }
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('REVIEW SUBMITTED'),
              ],
            ),
            backgroundColor: LunaraTheme.electricViolet,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }
}
