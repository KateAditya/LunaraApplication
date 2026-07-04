import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';

class RateSafetyScreen extends StatefulWidget {
  const RateSafetyScreen({super.key});

  @override
  State<RateSafetyScreen> createState() => _RateSafetyScreenState();
}

class _RateSafetyScreenState extends State<RateSafetyScreen> {
  bool? _feltSafe;
  String? _selectedIssue;
  final Set<String> _positiveBadges = {};
  final List<String> _issues = [
    'Inappropriate behavior',
    'Harassment',
    'Unsafe environment',
    'Emergency situation',
    'Other',
  ];

  final List<Map<String, dynamic>> _badges = [
    {'label': 'Great Vibe Buddy', 'icon': Icons.music_note},
    {'label': 'Respectful', 'icon': Icons.handshake},
    {'label': 'Fun Company', 'icon': Icons.emoji_emotions},
    {'label': 'Good Listener', 'icon': Icons.hearing},
  ];

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
                    _buildPrivacyNote(),
                    const SizedBox(height: 32),
                    _buildPartnerInfo(),
                    const SizedBox(height: 48),
                    _buildSafetyQuestion(),
                    if (_feltSafe == false) ...[
                      const SizedBox(height: 32),
                      _buildReportSection(),
                    ],
                    if (_feltSafe == true) ...[
                      const SizedBox(height: 32),
                      _buildPositiveBadges(),
                    ],
                    const SizedBox(height: 40),
                    if (_feltSafe != null) _buildSubmitButton(),
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
            'SAFETY CHECK',
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

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: LunaraTheme.electricViolet,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your feedback is 100% private and never shared with your partner.',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LunaraTheme.cardGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: LunaraTheme.premiumCardShadow,
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: LunaraTheme.electricViolet,
            child: Text(
              'SJ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rate your experience with',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sarah J.',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'ELARA VELVET',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'FEB 22',
                style: TextStyle(
                  color: LunaraTheme.electricViolet,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyQuestion() {
    return Column(
      children: [
        const Center(
          child: Text(
            'DID YOU FEEL SAFE TONIGHT?',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _feltSafe = true;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: _feltSafe == true
                        ? LunaraTheme.electricViolet.withValues(alpha: 0.05)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _feltSafe == true
                          ? LunaraTheme.electricViolet
                          : Colors.grey[200]!,
                      width: 2,
                    ),
                    boxShadow: _feltSafe == true
                        ? [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(
                                alpha: 0.1,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: _feltSafe == true
                            ? LunaraTheme.electricViolet
                            : Colors.grey[200],
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'YES',
                        style: TextStyle(
                          color: _feltSafe == true
                              ? LunaraTheme.electricViolet
                              : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _feltSafe = false;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: _feltSafe == false
                        ? Colors.red.withValues(alpha: 0.05)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _feltSafe == false
                          ? Colors.redAccent
                          : Colors.grey[200]!,
                      width: 2,
                    ),
                    boxShadow: _feltSafe == false
                        ? [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        color: _feltSafe == false
                            ? Colors.redAccent
                            : Colors.grey[200],
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'NO',
                        style: TextStyle(
                          color: _feltSafe == false
                              ? Colors.redAccent
                              : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReportSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TELL US MORE',
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          ..._issues.map((issue) {
            final isSelected = _selectedIssue == issue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => setState(() => _selectedIssue = issue),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.red.withValues(alpha: 0.05)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : Colors.grey[100]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected ? Colors.redAccent : Colors.grey[300],
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        issue,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.contact_phone_outlined,
                  color: Colors.amber[700],
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notify Emergency Contact?',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share your last known venue location with your emergency contact.',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: false,
                  onChanged: (_) {},
                  activeTrackColor: Colors.amber.withValues(alpha: 0.3),
                  activeThumbColor: Colors.amber,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositiveBadges() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AWARD A BADGE',
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Positive badges boost their match score',
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _badges.map((badge) {
            final label = badge['label'] as String;
            final icon = badge['icon'] as IconData;
            final isSelected = _positiveBadges.contains(label);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _positiveBadges.remove(label);
                  } else {
                    _positiveBadges.add(label);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: isSelected
                          ? LunaraTheme.electricViolet
                          : Colors.grey[400],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? LunaraTheme.electricViolet
                            : Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return LunaraActionButton(
      text: _feltSafe == false ? 'SUBMIT REPORT' : 'SUBMIT FEEDBACK',
      icon: _feltSafe == false
          ? Icons.report_gmailerrorred_rounded
          : Icons.send_rounded,
      onPressed: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  _feltSafe == false
                      ? 'REPORT SUBMITTED'
                      : 'FEEDBACK SUBMITTED',
                ),
              ],
            ),
            backgroundColor: _feltSafe == false
                ? Colors.redAccent
                : LunaraTheme.electricViolet,
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
