import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'package:lunara_app/screens/profile/profile_screen.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../discovery/venue_detail_screen.dart';

class PostDetailScreen extends StatelessWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? venue;

  const PostDetailScreen({super.key, required this.post, this.venue});

  @override
  Widget build(BuildContext context) {
    final String firstName = post['firstName'] ?? 'Lunara';
    final String lastName = post['lastName'] ?? 'User';
    final String venueName = post['venue'] ?? 'Unknown Venue';
    final String content = post['content'] ?? '';
    final String time = post['time'] ?? '';

    final String? photo =
        post['profilePhotoUrl'] ?? post['profilePhoto'] ?? post['image'];
    final bool isMyPost =
        post['userId']?.toString() == ApiService.currentUserId ||
        (post['user'] != null &&
            post['user']['id']?.toString() == ApiService.currentUserId);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, firstName, lastName, time, photo, post),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  // Post Content
                  Text(
                    content,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 40),
                  // Venue Context Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: LunaraTheme.electricViolet.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: LunaraTheme.electricViolet,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'HAPPENING AT',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    venueName.toUpperCase(),
                                    style: const TextStyle(
                                      fontFamily: 'AllroundGothic',
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                if (venue != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          VenueDetailScreen(venue: venue!),
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'VIEW',
                                style: TextStyle(
                                  color: LunaraTheme.electricViolet,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: isMyPost
          ? const SizedBox.shrink()
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LunaraTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFb952eb).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      final success = await ApiService.requestToJoinPartyPlan(
                        post['id'],
                      );
                      if (success) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              behavior: SnackBarBehavior.floating,
                              content: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LunaraTheme.purpleGradient,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: LunaraTheme.electricViolet
                                          .withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'YOUR REQUEST TO JOIN THE VIBE HAS BEEN SENT!',
                                        style: TextStyle(
                                          fontFamily: 'AllroundGothic',
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to send request. You may have already requested.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'JOIN THE VIBE',
                          style: TextStyle(
                            fontFamily: 'AllroundGothic',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    String firstName,
    String lastName,
    String time,
    String? photo,
    Map<String, dynamic> post,
  ) {
    String? finalPhoto = photo;
    if (finalPhoto != null &&
        finalPhoto.startsWith('/') &&
        !finalPhoto.startsWith('assets')) {
      finalPhoto = 'http://103.224.247.35:9076$finalPhoto';
    }

    User? profileUser;
    try {
      profileUser = User.fromJson(post['user'] ?? post);
    } catch (_) {}

    int? displayAge = profileUser?.age;
    if (displayAge == null && profileUser?.dateOfBirth != null) {
      try {
        final dob = DateTime.parse(profileUser!.dateOfBirth!);
        final now = DateTime.now();
        displayAge = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          displayAge--;
        }
      } catch (_) {}
    }
    final bool isVerified = profileUser?.isVerified ?? false;

    return SliverAppBar(
      expandedHeight: 450,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.3),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        // Profile view button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            child: IconButton(
              icon: const Icon(Icons.person, color: Colors.white),
              onPressed: () {
                User? profileUser;
                try {
                  profileUser = User.fromJson(post['user'] ?? post);
                } catch (e) {
                  // Fallback if parsing fails
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(user: profileUser),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (finalPhoto != null &&
                finalPhoto.isNotEmpty &&
                finalPhoto.startsWith('http'))
              Image.network(
                finalPhoto,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  decoration: const BoxDecoration(
                    gradient: LunaraTheme.deepPurpleGradient,
                  ),
                ),
              )
            else if (finalPhoto != null &&
                finalPhoto.isNotEmpty &&
                finalPhoto.startsWith('assets'))
              Image.asset(finalPhoto, fit: BoxFit.cover)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LunaraTheme.deepPurpleGradient,
                ),
              ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 30,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$firstName $lastName${displayAge != null ? ', $displayAge' : ''}'
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          fontFamily: 'AllroundGothic',
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 28,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          time,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
