import 'package:flutter/material.dart';

/// App Tour Service - All tour overlays completely removed for smooth, non-blocking UI.
class AppTourService {
  // Dashboard Keys (retained for backward-compatible references)
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

  // All tour methods are safe no-ops (App Tour removed for performance)
  static Future<void> markUserAsNew() async {}
  static Future<void> showDashboardTour(BuildContext context) async {}
  static Future<void> showDiscoveryTour(BuildContext context) async {}
  static Future<void> showPlanHubTour(BuildContext context) async {}
  static Future<void> showVenueDetailTour(BuildContext context) async {}
  static Future<void> showCreatePlanTour(BuildContext context) async {}
  static Future<void> showStrangersMeetTour(BuildContext context) async {}
  static Future<void> showGroupPartyTour(BuildContext context) async {}
  static Future<void> showGroupPartyBookingTour(BuildContext context) async {}
}
