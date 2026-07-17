import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../widgets/lunara_profile_image.dart';
import '../../services/api_service.dart';

class SafetyCheckScreen extends StatefulWidget {
  final User? user;
  const SafetyCheckScreen({super.key, this.user});

  @override
  State<SafetyCheckScreen> createState() => _SafetyCheckScreenState();
}

class _SafetyCheckScreenState extends State<SafetyCheckScreen> {
  bool? _feltSafe;

  void _showFeedbackDialog(bool feltSafe) {
    final List<String> prebuiltOptions = feltSafe
        ? [
            'Polite & Friendly',
            'Respectful & Safe',
            'Great communication',
            'Felt very comfortable',
            'Arrived on time',
          ]
        : [
            'Rude or aggressive',
            'Made me feel uncomfortable',
            'Did not match profile',
            'Inappropriate behavior',
            'Left early without reason',
          ];

    final selectedOptions = <String>{};
    final commentController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 48,
                ),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            feltSafe ? Icons.sentiment_very_satisfied_rounded : Icons.warning_amber_rounded,
                            color: feltSafe ? Colors.green : Colors.red,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              feltSafe ? 'Share details' : 'Report Concern',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'AllroundGothic',
                                color: Colors.black,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black54),
                            onPressed: isSubmitting ? null : () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        feltSafe
                            ? 'What went well? Select one or more prebuilt reasons or enter your opinion:'
                            : 'What went wrong? Select one or more reasons or describe below (confidential):',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Prebuilt choices wrap
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: prebuiltOptions.map((option) {
                          final isSelected = selectedOptions.contains(option);
                          return ChoiceChip(
                            label: Text(
                              option,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: LunaraTheme.electricViolet,
                            backgroundColor: Colors.grey[100],
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
                              ),
                            ),
                            onSelected: isSubmitting
                                ? null
                                : (selected) {
                                    setDialogState(() {
                                      if (selected) {
                                        selectedOptions.add(option);
                                      } else {
                                        selectedOptions.remove(option);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Your Custom Feedback (Optional)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentController,
                        enabled: !isSubmitting,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Describe your experience...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Action button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LunaraTheme.electricViolet,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setDialogState(() {
                                  isSubmitting = true;
                                });

                                final success = await ApiService.submitSafetyCheck(
                                  partnerId: widget.user?.id ?? '',
                                  feltSafe: feltSafe,
                                  prebuiltAnswers: selectedOptions.toList(),
                                  opinion: commentController.text.trim(),
                                );

                                if (success) {
                                  if (context.mounted) {
                                    Navigator.pop(context); // Close dialog
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Thank you! Your feedback has been safely submitted.'),
                                        backgroundColor: LunaraTheme.electricViolet,
                                      ),
                                    );
                                    Navigator.pop(context); // Go back to settings/profile
                                  }
                                } else {
                                  setDialogState(() {
                                    isSubmitting = false;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to submit feedback. Please try again.'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'SUBMIT FEEDBACK',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SAFETY CHECK',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 2,
            fontFamily: 'AllroundGothic',
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Privacy Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: LunaraTheme.electricViolet, size: 20),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Your feedback is 100% private and never shared with your partner.',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Experience Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: LunaraTheme.premiumCardShadow,
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: Row(
                children: [
                  LunaraProfileImage(
                    user: widget.user,
                    radius: 28,
                    showGradientBorder: true,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate your experience with',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.user?.fullName ?? 'Sarah J.',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
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
            ),
            const SizedBox(height: 48),
            // Question
            const Text(
              'DID YOU FEEL SAFE TONIGHT?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _buildSafetyButton(
                    'YES',
                    Icons.check_circle_outline_rounded,
                    _feltSafe == true,
                    () {
                      setState(() => _feltSafe = true);
                      _showFeedbackDialog(true);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSafetyButton(
                    'NO',
                    Icons.warning_amber_rounded,
                    _feltSafe == false,
                    () {
                      setState(() => _feltSafe = false);
                      _showFeedbackDialog(false);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: isSelected ? LunaraTheme.electricViolet.withValues(alpha: 0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300],
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? LunaraTheme.electricViolet : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
