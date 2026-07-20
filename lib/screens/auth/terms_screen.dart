import 'package:flutter/material.dart';
import '../../core/theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const String termsText = '''App Name: Powered by: SSKL WORLD.
Jurisdiction: Pune, Maharashtra, India

TERMS & CONDITIONS

These Terms & Conditions ("Terms") constitute a legally binding agreement between You ("User", "You", "Your") and SSKL WORLD, the owner and operator of the digital platform known as LUNARA ("LUNARA", "Platform", "Company", "We", "Us", or "Our").

These Terms govern Your access to and use of the LUNARA mobile application, website, software, platform services, social discovery features, matchmaking tools, venue discovery services, bookings, subscriptions, content, communications, events, promotional offers, and all associated services provided by LUNARA.

By accessing, downloading, browsing, registering on, or using the Platform in any manner whatsoever, You acknowledge that You have read, understood, and agreed to be legally bound by these Terms, the Privacy Policy, Refund & Cancellation Policy, Community Guidelines, Venue Partner Policies, and all other policies issued by LUNARA from time to time.

IF YOU DO NOT AGREE TO THESE TERMS, YOU MUST IMMEDIATELY STOP USING THE PLATFORM.''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Terms and Conditions',
          style: LunaraTheme.headingStyle.copyWith(
            fontSize: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terms and Conditions',
              style: LunaraTheme.headingStyle.copyWith(
                fontSize: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '''App Name: Powered by: SSKL WORLD.
Jurisdiction: Pune, Maharashtra, India

TERMS & CONDITIONS

These Terms & Conditions (“Terms”) constitute a legally binding agreement between You (“User”, “You”, “Your”) and SSKL WORLD, the owner and operator of the digital platform known as LUNARA (“LUNARA”, “Platform”, “Company”, “We”, “Us”, or “Our”).

These Terms govern Your access to and use of the LUNARA mobile application, website, software, platform services, social discovery features, matchmaking tools, venue discovery services, bookings, subscriptions, content, communications, events, promotional offers, and all associated services provided by LUNARA.

By accessing, downloading, browsing, registering on, or using the Platform in any manner whatsoever, You acknowledge that You have read, understood, and agreed to be legally bound by these Terms, the Privacy Policy, Refund & Cancellation Policy, Community Guidelines, Venue Partner Policies, and all other policies issued by LUNARA from time to time.

IF YOU DO NOT AGREE TO THESE TERMS, YOU MUST IMMEDIATELY STOP USING THE PLATFORM.

1. ABOUT THE PLATFORM
a) LUNARA is a technology-enabled social discovery and venue interaction platform designed to facilitate:
• Discovery of pubs, clubs, lounges, cafés, restaurants, rooftop venues, nightlife venues, events, and social experiences;
• Social interaction between users with similar interests or venue preferences;
• Match-based social networking and meetup planning;
• Venue exploration and booking assistance;
• Access to offers, promotions, subscriptions, and social engagement tools.

b) LUNARA operates solely as an intermediary technology platform and digital facilitator.
c) LUNARA does not own, control, supervise, operate, or manage any listed venue unless specifically stated otherwise.
d) LUNARA does not provide food, beverages, transportation, security services, alcohol service, hospitality operations, or event management services.
e) All services relating to venue operations, including entry approval, pricing, menu availability, crowd management, security arrangements, alcohol service, and hospitality standards are solely managed by the respective venues.
f) LUNARA merely facilitates user discovery, communication, and interaction through digital means.

2. INTERMEDIARY STATUS & SAFE HARBOUR PROTECTION
a) LUNARA functions as an “Intermediary” under the provisions of the Information Technology Act, 2000 and applicable rules thereunder.
b) LUNARA is entitled to protection under Section 79 of the Information Technology Act, 2000 for third-party information hosted on the Platform.

LUNARA does not:
• Initiate transmission of user-generated content;
• Select the receiver of such content;
• Modify or alter user-generated content;
• Endorse user conduct or representations.

c) Users acknowledge that all information, content, chats, profile details, uploads, interactions, and communications are generated solely by users.
d) Users remain solely responsible for all content uploaded, shared, transmitted, or published through the Platform.

3. ELIGIBILITY & USER REPRESENTATIONS
a) Users must be at least eighteen (18) years of age to access or use the Platform.
b) By registering or using the Platform, You represent and warrant that:
• You are legally competent to enter into a binding contract under Indian law;
• All information submitted by You is accurate, complete, and truthful;
• You are not impersonating any person or entity;
• You shall comply with all applicable laws and regulations.

c) Users below the legal drinking age applicable in their respective State or Union Territory shall not use alcohol-related features or services.
d) LUNARA reserves the right to request identity proof, age verification, selfie verification, mobile verification, or any additional information at its sole discretion.
e) Failure to complete verification procedures may result in suspension, restriction, or permanent termination of the account.

4. ACCOUNT REGISTRATION & SECURITY
a) Users are solely responsible for maintaining confidentiality of their login credentials, passwords, OTPs, and account access information.
b) Users shall not share account access with any third party.
c) All activities conducted through a user account shall be deemed to have been conducted by the registered user.
d) Users must immediately notify LUNARA regarding any suspected unauthorized access, hacking attempt, account misuse, or security breach.
e) LUNARA shall not be liable for losses arising due to stolen credentials, hacking, negligence, OTP misuse, phishing, or unauthorized access.

5. USER CONDUCT & COMMUNITY GUIDELINES
Users agree that they shall not:
• Harass, threaten, abuse, stalk, intimidate, or exploit other users;
• Upload fake profiles or misleading information;
• Engage in scams, cheating, fraud, impersonation, extortion, or blackmail;
• Promote escort services, prostitution, illegal activities, or unlawful conduct;
• Upload obscene, pornographic, sexually explicit, defamatory, hateful, vulgar, discriminatory, or unlawful content;
• Upload viruses, malware, spam, bots, scripts, or malicious software;
• Misuse booking systems or create fake bookings;
• Engage in repeated no-shows or time-pass bookings;
• Violate intellectual property rights;
• Share another person’s personal information without consent;
• Conduct political campaigning or unlawful promotions;
• Use the Platform for unauthorized commercial solicitation.

LUNARA reserves the unrestricted right to suspend, restrict, remove, or permanently ban any account violating these Terms.

6. SEXUAL HARASSMENT & MISCONDUCT POLICY
Users shall not engage in:
• Sexual harassment;
• Non-consensual conduct;
• Stalking;
• Inappropriate touching;
• Sharing explicit content without consent;
• Sexual exploitation;
• Threatening behaviour;
• Coercion or intimidation.

a. Any complaint relating to sexual misconduct may result in immediate suspension or permanent termination of the user account.
b. LUNARA reserves the right to cooperate with law enforcement authorities, cyber cells, governmental agencies, and courts regarding unlawful conduct.

7. BOOKINGS, MATCHES & SOCIAL INTERACTIONS
a) LUNARA may facilitate social discovery, venue interaction, matchmaking, meetup planning, and booking assistance.
b) LUNARA does not guarantee:
• Successful matches;
• User compatibility;
• Emotional compatibility;
• Attendance at venues;
• Relationships;
• Continuation of communication;
• Quality of interactions.

c) A booking shall be considered confirmed only upon successful payment and system confirmation.
d) All meetings and interactions between users are voluntary and undertaken entirely at users’ own discretion and risk.
e) Users are strongly advised to:
• Meet only in public places;
• Independently verify identities;
• Avoid sharing sensitive financial or personal information;
• Arrange safe transportation;
• Discuss bill splitting in advance.
f) LUNARA shall not be liable for failed meetings, disputes, emotional distress, assault, theft, fraud, financial disputes, misconduct, or personal disagreements.

8. ASSUMPTION OF RISK
a) Users acknowledge that interacting with strangers, visiting nightlife venues, consuming alcohol, attending social gatherings, and participating in real-world meetings involve inherent risks.
b) Users voluntarily assume all risks associated with:
• Social interactions;
• Real-world meetings;
• Alcohol-serving venues;
• Nightlife activities;
• Transportation;
• Venue environments;
• Personal relationships.

c) Users agree that they use the Platform entirely at their own discretion and risk.

9. VENUE LISTINGS & VENUE DISCLAIMER
a) Venue information displayed on the Platform may be sourced from venue partners, public sources, advertisers, or third-party data providers.
b) LUNARA does not guarantee accuracy, completeness, or availability of venue information at all times.
c) Venues remain independently owned and operated businesses.
d) LUNARA shall not be responsible for:
• Entry refusal;
• Venue overcrowding;
• Event cancellations;
• Menu changes;
• Pricing variations;
• Staff conduct;
• Service quality;
• Security arrangements;
• Alcohol-related incidents;
• Venue negligence;
• Customer disputes.
e) Users must independently comply with all venue policies, including dress code, age restrictions, identity verification requirements, and venue conduct rules.

10. ALCOHOL & NIGHTLIFE DISCLAIMER
a) LUNARA does not encourage irresponsible alcohol consumption.
b) Venues independently control alcohol service and age verification procedures.
c) Users are solely responsible for compliance with applicable drinking-age laws and local regulations.
d) LUNARA shall not be liable for:
• Alcohol-related accidents;
• Intoxication;
• Drunk driving;
• Medical emergencies;
• Fights or altercations;
• Injuries occurring at venues.

e) Users are responsible for arranging safe travel and transportation after venue visits.

11. AI, ALGORITHMS & RECOMMENDATION DISCLAIMER
a) LUNARA may use automated systems, artificial intelligence tools, recommendation engines, algorithms, or behavioural analytics to improve user experience and provide suggestions.
b) Any recommendations, match suggestions, rankings, compatibility indicators, or venue suggestions generated through automated systems are indicative only.
c) Such recommendations shall not constitute guarantees, endorsements, verification, or assurances by LUNARA.

12. CONTENT POLICY
Users shall not upload, publish, transmit, or share content that:
• Is unlawful;
• Is sexually explicit or pornographic;
• Violates privacy rights;
• Promotes violence or hate;
• Infringes intellectual property rights;
• Is defamatory or misleading;
• Encourages criminal conduct;
• Contains malware or harmful code.
LUNARA reserves the right to remove such content without prior notice

13. CONTENT OWNERSHIP & LICENSE
a) Users retain ownership of content uploaded by them.
b) By uploading content, users grant LUNARA a worldwide, perpetual, royalty-free, transferable, sublicensable, non-exclusive license to:
• Use;
• Host;
• Reproduce;
• Modify;
• Promote;
• Display;
• Publish;
• Advertise;
c) Distribute such content for operational, promotional, safety, moderation, marketing, research, analytics, and platform improvement purposes.
d) Users confirm that they possess all legal rights necessary to upload such content.

14. PAYMENTS, SUBSCRIPTIONS & COMMERCIAL TERMS
a) LUNARA may offer:
• Premium subscriptions;
• Visibility boosts;
• Promotional packages;
• Booking services;
• Event passes;
• Paid features;
• Advertising opportunities.

b) All applicable taxes including GST shall be payable by users wherever applicable.
c) Subscription fees, platform charges, convenience fees, taxes, and pricing structures may be revised at any time.
d) Users authorize LUNARA and its payment partners to process payments through UPI, cards, wallets, net banking, app stores, and payment gateways.
e) LUNARA shall not be liable for payment gateway failures, banking interruptions, delayed settlements, or technical payment issues.
f) Chargeback abuse, fraudulent payment disputes, or suspicious transactions may result in account suspension.

15. REFUND & CANCELLATION POLICY
a) Once a booking, subscription, promotion, or reservation is confirmed, it shall generally be treated as non-refundable.
b) No refunds shall be provided for:
• User no-shows;
• Failed meetings;
• Personal dissatisfaction;
• Last-minute cancellations;
• Venue refusal due to dress code or intoxication;
• Change of plans.
c) Refund exceptions may only be considered in cases of duplicate transactions, verified technical failures, or payment deduction without successful confirmation.
d) LUNARA reserves sole discretion regarding approval or rejection of refund requests.

16. CYBER FRAUD & SECURITY PROTECTION
a. Users shall not engage in:
• OTP fraud;
• Fake payment screenshots;
• Identity theft;
• Phishing;
• Account hacking;
• Unauthorized access;
• Payment fraud;
• Misrepresentation.
b. LUNARA reserves the right to report fraudulent or unlawful activities to cyber cells, police authorities, banks, financial institutions, and governmental agencies.

17. DATA PRIVACY & USER CONSENT
a) By using the Platform, users consent to collection, storage, processing, and usage of personal information in accordance with applicable laws including the Digital Personal Data Protection Act, 2023.
b) Location data may be used to provide venue recommendations and nearby experiences.
c) User data may be shared with venue partners solely for booking fulfilment and operational coordination.
d) Users consent to receiving:
• Notifications;
• Emails;
• Promotional communications;
• WhatsApp messages;
• SMS alerts;
• Security notifications.
e) Users may request deletion of their account subject to applicable legal retention obligations.
f) LUNARA adopts commercially reasonable security measures but does not guarantee absolute security of digital systems

18. INTELLECTUAL PROPERTY RIGHTS
a) All intellectual property relating to the Platform including:
• Software;
• Designs;
• UI/UX;
• Branding;
• Databases;
• Algorithms;
• Trade dress;
• Graphics;
• Source code;
• Platform architecture;
• Marketing materials;
Shall remain the exclusive property of LUNARA and/or SSKL WORLD.

b) Users shall not copy, reproduce, reverse engineer, scrape, republish, exploit, distribute, or commercially use any Platform material without prior written consent.

19. ACCOUNT SUSPENSION & TERMINATION
LUNARA reserves the unrestricted right to suspend, restrict, disable, or permanently terminate user accounts without prior notice for:
• Policy violations;
• Fraudulent conduct;
• Illegal activities;
• Fake profiles;
• Safety concerns;
• Harassment;
• Chargeback abuse;
• Platform misuse;
• Reputation risks.
Termination shall not affect accrued liabilities or legal remedies available to LUNARA.

20. DISCLAIMER OF WARRANTIES
THE PLATFORM IS PROVIDED ON AN “AS IS”, “AS AVAILABLE”, AND “BEST EFFORT BASIS”.

LUNARA DISCLAIMS ALL WARRANTIES INCLUDING:
• MERCHANTABILITY;
• FITNESS FOR A PARTICULAR PURPOSE;
• ACCURACY;
• NON-INFRINGEMENT;
• UNINTERRUPTED ACCESS;
• ERROR-FREE OPERATION.

LUNARA DOES NOT GUARANTEE:
• Successful matches;
• Venue entry;
• User authenticity;
• Safety of interactions;
• Relationship outcomes;
• Service quality of venues.

21. LIMITATION OF LIABILITY
21.1 To the maximum extent permitted under applicable law, LUNARA, SSKL WORLD, affiliates, directors, employees, agents, and partners shall not be liable for:
• Indirect damages;
• Consequential damages;
• Emotional distress;
• Personal injury;
• Loss of profits;
• Reputational harm;
• Property damage;
• Venue incidents;
• User misconduct;
• Criminal acts;
• Alcohol-related incidents;
• Financial disputes.

21.2 Total aggregate liability of LUNARA shall not exceed the amount paid by the user to the Platform during the preceding three (3) months.

22. INDEMNITY
Users agree to indemnify, defend, and hold harmless LUNARA, SSKL WORLD, affiliates, officers, directors, employees, and partners from any claims, damages, liabilities, penalties, proceedings, losses, costs, or expenses arising from:
• User misconduct;
• Policy violations;
• Fraud;
• Third-party disputes;
• Illegal activities;
• Venue disputes;
• Intellectual property infringement;
• User-generated content.

23. FORCE MAJEURE
LUNARA shall not be liable for delays or failures arising from events beyond reasonable control including:
• Natural disasters;
• Pandemic situations;
• Government restrictions;
• Curfews;
• Cyberattacks;
• Internet failures;
• Venue shutdowns;
• Civil unrest;
• Technical outages;
• Payment gateway interruptions.

24. ELECTRONIC CONSENT
By clicking “I Agree”, “Accept”, “Continue”, “Register”, or by using the Platform, users electronically execute and consent to these Terms under applicable laws governing electronic contracts and records.

25. GOVERNING LAW, ARBITRATION & JURISDICTION
a) These Terms shall be governed by laws of India.
b) Any dispute arising out of or relating to these Terms shall first be attempted to be resolved amicably.
c) Failing amicable settlement, disputes shall be referred to arbitration under the Arbitration and Conciliation Act, 1996.
d) Arbitration shall be conducted by a Sole Arbitrator appointed by LUNARA.
e) The seat and venue of arbitration shall be Pune, Maharashtra.
f) Proceedings shall be conducted in English language.
g) Courts situated at Pune, Maharashtra shall have exclusive jurisdiction.

26. MODIFICATIONS TO TERMS
LUNARA reserves the right to modify, revise, amend, or update these Terms at any time without prior notice.
Continued use of the Platform after such modifications shall constitute acceptance of revised Terms.

27. SEVERABILITY
If any provision of these Terms is held invalid or unenforceable, the remaining provisions shall continue in full force and effect.

28. ENTIRE AGREEMENT
These Terms together with the Privacy Policy, Refund Policy, Community Guidelines, Venue Policies, and related policies constitute the complete agreement between users and LUNARA.

29. CONTACT DETAILS
LUNARA – Powered by SSKL WORLD
Pune, Maharashtra, India
Email: __________________
Support: __________________''',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
