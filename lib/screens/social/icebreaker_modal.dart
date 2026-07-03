import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class IcebreakerModal extends StatefulWidget {
  const IcebreakerModal({super.key});

  /// Shows the modal and returns the selected icebreaker text, or null if dismissed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const IcebreakerModal(),
    );
  }

  @override
  State<IcebreakerModal> createState() => _IcebreakerModalState();
}

class _IcebreakerModalState extends State<IcebreakerModal> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  static const _fallback = [
    {'icon': '🔥', 'text': 'Obsidian or Elara tonight?'},
    {'icon': '🎧', 'text': 'Favorite DJ in the city?'},
    {'icon': '🍸', 'text': 'What is your go-to signature cocktail?'},
    {'icon': '✨', 'text': 'Best rooftop view you have seen?'},
    {'icon': '🎵', 'text': 'Melodic House or Hard Techno?'},
    {'icon': '⚡', 'text': 'Night owl or early bird?'},
    {'icon': '🌆', 'text': 'Favorite city for nightlife?'},
    {'icon': '🥂', 'text': 'Champagne or cocktails?'},
    {'icon': '🎤', 'text': 'Karaoke or dance floor?'},
    {'icon': '🌙', 'text': 'Underground or mainstream?'},
  ];

  static const _icons = ['🔥', '🎧', '🍸', '✨', '🎵', '⚡', '🌆', '🥂', '🎤', '🌙'];

  @override
  void initState() {
    super.initState();
    _fetchIcebreakers();
  }

  Future<void> _fetchIcebreakers() async {
    try {
      final live = await ApiService.fetchIcebreakers();
      if (mounted) {
        setState(() {
          _items = live.isNotEmpty
              ? live.asMap().entries.map((e) {
                  final text = e.value['text'] ?? e.value['prompt'] ?? e.value['content'] ?? '';
                  final icon = e.value['icon'] ?? _icons[e.key % _icons.length];
                  return {'icon': icon, 'text': text};
                }).toList()
              : _fallback;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = _fallback;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Text(
            'ICEBREAKERS',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation with a vibe.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, item['text'] as String),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: LunaraTheme.cardGradient,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: LunaraTheme.premiumCardShadow,
                              border: Border.all(
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(item['icon']! as String, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    item['text']! as String,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.send_rounded, color: LunaraTheme.electricViolet, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
