import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/app_tour_tooltip.dart';

class AppTourService {
  // Dashboard Keys
  static final GlobalKey homeTabKey = GlobalKey();
  static final GlobalKey matchesTabKey = GlobalKey();
  static final GlobalKey postTabKey = GlobalKey();
  static final GlobalKey messagesTabKey = GlobalKey();
  static final GlobalKey profileTabKey = GlobalKey();
  static final GlobalKey vipUpgradeKey = GlobalKey();

  // Discovery Keys
  static final GlobalKey searchBarKey = GlobalKey();
  static final GlobalKey upcomingNightsKey = GlobalKey();

  // Plan Hub Keys
  static final GlobalKey createPlanKey = GlobalKey();
  static final GlobalKey groupPartyKey = GlobalKey();
  static final GlobalKey strangersMeetKey = GlobalKey();

  // Venue Detail Keys
  static final GlobalKey venueDirectionsKey = GlobalKey();
  static final GlobalKey venueBookNowKey = GlobalKey();

  // Sub-Plan Keys
  static final GlobalKey createPlanVenueSearchKey = GlobalKey();
  static final GlobalKey createPlanPostButtonKey = GlobalKey();
  
  static final GlobalKey strangersMeetSearchKey = GlobalKey();
  static final GlobalKey strangersMeetArrangeButtonKey = GlobalKey();

  static final GlobalKey groupPartyBannerKey = GlobalKey();
  static final GlobalKey groupPartyFriendsKey = GlobalKey();
  static final GlobalKey groupPartyProceedButtonKey = GlobalKey();

  static const String _hasSeenDashboardTourKey = 'has_seen_dashboard_tour';
  static const String _hasSeenDiscoveryTourKey = 'has_seen_discovery_tour';
  static const String _hasSeenPlanHubTourKey = 'has_seen_plan_hub_tour';
  static const String _hasSeenVenueDetailTourKey = 'has_seen_venue_detail_tour';
  static const String _hasSeenCreatePlanTourKey = 'has_seen_create_plan_tour';
  static const String _hasSeenStrangersMeetTourKey = 'has_seen_strangers_meet_tour';
  static const String _hasSeenGroupPartyTourKey = 'has_seen_group_party_tour';
  static const String _hasSeenGroupPartyBookingTourKey = 'has_seen_group_party_booking_tour';

  static Future<void> markUserAsNew() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenDashboardTourKey, false);
    await prefs.setBool(_hasSeenDiscoveryTourKey, false);
    await prefs.setBool(_hasSeenPlanHubTourKey, false);
    await prefs.setBool(_hasSeenVenueDetailTourKey, false);
    await prefs.setBool(_hasSeenCreatePlanTourKey, false);
    await prefs.setBool(_hasSeenStrangersMeetTourKey, false);
    await prefs.setBool(_hasSeenGroupPartyTourKey, false);
    await prefs.setBool(_hasSeenGroupPartyBookingTourKey, false);
  }

  static Future<void> showDashboardTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenDashboardTourKey) ?? false;

    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "home_tab",
        keyTarget: homeTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Home',
                description: 'Discover the best venues and parties around you.',
                currentStep: 1,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "matches_tab",
        keyTarget: matchesTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Matches',
                description: 'Find your vibe-mates and see who matches with you.',
                currentStep: 2,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "post_tab",
        keyTarget: postTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Host a Party',
                description: 'Create your own Party Plans and invite others.',
                currentStep: 3,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "messages_tab",
        keyTarget: messagesTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Messages',
                description: 'Chat with your matches and coordinate plans safely.',
                currentStep: 4,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "profile_tab",
        keyTarget: profileTabKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Profile',
                description: 'Update your vibe, photos, and settings.',
                currentStep: 5,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "vip_upgrade",
        keyTarget: vipUpgradeKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Go VIP',
                description: 'Unlock premium features and see who likes you.',
                currentStep: 6,
                totalSteps: 6,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
                isLastStep: true,
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        prefs.setBool(_hasSeenDashboardTourKey, true);
      },
      onSkip: () {
        prefs.setBool(_hasSeenDashboardTourKey, true);
        return true;
      },
    ).show(context: context);
  }

  static Future<void> showDiscoveryTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenDiscoveryTourKey) ?? false;

    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "upcoming_nights",
        keyTarget: upcomingNightsKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Upcoming Nights',
                description: 'Discover the hottest upcoming events and parties.',
                currentStep: 1,
                totalSteps: 1,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
                isLastStep: true,
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        prefs.setBool(_hasSeenDiscoveryTourKey, true);
      },
      onSkip: () {
        prefs.setBool(_hasSeenDiscoveryTourKey, true);
        return true;
      },
    ).show(context: context);
  }

  static Future<void> showPlanHubTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenPlanHubTourKey) ?? false;

    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "create_plan",
        keyTarget: createPlanKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Create a Plan',
                description: 'Host your own party and invite people.',
                currentStep: 1,
                totalSteps: 3,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "group_party",
        keyTarget: groupPartyKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Group Party',
                description: 'Join exciting group parties happening around.',
                currentStep: 2,
                totalSteps: 3,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "strangers_meet",
        keyTarget: strangersMeetKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Strangers Meet',
                description: 'Arrange a meetup to make new connections safely.',
                currentStep: 3,
                totalSteps: 3,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
                isLastStep: true,
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        prefs.setBool(_hasSeenPlanHubTourKey, true);
      },
      onSkip: () {
        prefs.setBool(_hasSeenPlanHubTourKey, true);
        return true;
      },
    ).show(context: context);
  }

  static Future<void> showVenueDetailTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenVenueDetailTourKey) ?? false;

    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "venue_directions",
        keyTarget: venueDirectionsKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Directions',
                description: 'Get directions to this venue instantly.',
                currentStep: 1,
                totalSteps: 2,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "venue_book_now",
        keyTarget: venueBookNowKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return AppTourTooltip(
                title: 'Book Now',
                description: 'Ready to go? Book your spot here.',
                currentStep: 2,
                totalSteps: 2,
                onNext: controller.next,
                onPrevious: controller.previous,
                onSkip: controller.skip,
                isLastStep: true,
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "SKIP",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        prefs.setBool(_hasSeenVenueDetailTourKey, true);
      },
      onSkip: () {
        prefs.setBool(_hasSeenVenueDetailTourKey, true);
        return true;
      },
    ).show(context: context);
  }

  static Future<void> showCreatePlanTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenCreatePlanTourKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "create_plan_search",
        keyTarget: createPlanVenueSearchKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => AppTourTooltip(
              title: 'Find a Venue',
              description: 'Search and pick the perfect venue for your plan.',
              currentStep: 1,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "create_plan_post",
        keyTarget: createPlanPostButtonKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => AppTourTooltip(
              title: 'Post Plan',
              description: 'Post it to invite friends or make it public.',
              currentStep: 2,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
              isLastStep: true,
            ),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      onFinish: () => prefs.setBool(_hasSeenCreatePlanTourKey, true),
      onSkip: () { prefs.setBool(_hasSeenCreatePlanTourKey, true); return true; },
    ).show(context: context);
  }

  static Future<void> showStrangersMeetTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenStrangersMeetTourKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "strangers_meet_search",
        keyTarget: strangersMeetSearchKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => AppTourTooltip(
              title: 'Pick a Safe Venue',
              description: 'Choose a verified venue to meet new people safely.',
              currentStep: 1,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "strangers_meet_arrange",
        keyTarget: strangersMeetArrangeButtonKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => AppTourTooltip(
              title: 'Arrange Meet',
              description: 'Publish your meet and see who wants to join.',
              currentStep: 2,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
              isLastStep: true,
            ),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      onFinish: () => prefs.setBool(_hasSeenStrangersMeetTourKey, true),
      onSkip: () { prefs.setBool(_hasSeenStrangersMeetTourKey, true); return true; },
    ).show(context: context);
  }

  static Future<void> showGroupPartyTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenGroupPartyTourKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "group_party_banner",
        keyTarget: groupPartyBannerKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => AppTourTooltip(
              title: 'Group Perks',
              description: 'Join Lunara to get zero fees on group bookings.',
              currentStep: 1,
              totalSteps: 1,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
              isLastStep: true,
            ),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      onFinish: () => prefs.setBool(_hasSeenGroupPartyTourKey, true),
      onSkip: () { prefs.setBool(_hasSeenGroupPartyTourKey, true); return true; },
    ).show(context: context);
  }

  static Future<void> showGroupPartyBookingTour(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_hasSeenGroupPartyBookingTourKey) ?? false;
    if (hasSeen) return;
    if (!context.mounted) return;

    final targets = [
      TargetFocus(
        identify: "group_party_friends",
        keyTarget: groupPartyFriendsKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => AppTourTooltip(
              title: 'Add Friends',
              description: 'Select how many friends are joining your party.',
              currentStep: 1,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "group_party_proceed",
        keyTarget: groupPartyProceedButtonKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => AppTourTooltip(
              title: 'Proceed',
              description: 'Review pricing and proceed to payment.',
              currentStep: 2,
              totalSteps: 2,
              onNext: controller.next,
              onPrevious: controller.previous,
              onSkip: controller.skip,
              isLastStep: true,
            ),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      onFinish: () => prefs.setBool(_hasSeenGroupPartyBookingTourKey, true),
      onSkip: () { prefs.setBool(_hasSeenGroupPartyBookingTourKey, true); return true; },
    ).show(context: context);
  }
}
