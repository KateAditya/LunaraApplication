import '../services/api_service.dart';

class User {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String? profilePhoto;
  final String? bio;
  final String? city;
  final String? gender;

  // New properties from user profile and preferences response
  final List<String> photos;
  final List<Map<String, String>> photoDetails;
  final int? age;
  final String? displayName;
  final String? occupation;
  final String? company;
  final String? education;
  final List<String> lookingFor;
  final List<String> interests;
  final List<String> nightlifePreference;
  final List<String> musicPreference;
  final String? smokingPreference;
  final List<String> drinkPreference;
  final String? budgetRange;
  final int? minBudget;
  final int? maxBudget;
  final List<String> preferredGenders;
  final int? minAgePreference;
  final int? maxAgePreference;
  final int? matchDistanceKm;
  final bool invisibleMode;
  final bool showMeInMatching;
  final bool bookingAlertsEnabled;
  final String? dateOfBirth;
  final bool isVerified;
  final int superLikesCount;
  final int plansCount;
  final String subscriptionTier; // FREE, CORE, PLUS, PRO, ELITE
  final int bookingsCount;
  final int matchesCount;
  final int pointsCount;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    this.profilePhoto,
    this.bio,
    this.city,
    this.gender,
    this.photos = const [],
    this.photoDetails = const [],
    this.age,
    this.displayName,
    this.occupation,
    this.company,
    this.education,
    this.lookingFor = const [],
    this.interests = const [],
    this.nightlifePreference = const [],
    this.musicPreference = const [],
    this.smokingPreference,
    this.drinkPreference = const [],
    this.budgetRange,
    this.minBudget,
    this.maxBudget,
    this.preferredGenders = const [],
    this.minAgePreference,
    this.maxAgePreference,
    this.matchDistanceKm,
    this.invisibleMode = false,
    this.showMeInMatching = true,
    this.bookingAlertsEnabled = true,
    this.dateOfBirth,
    this.isVerified = false,
    this.superLikesCount = 0,
    this.plansCount = 0,
    this.subscriptionTier = 'FREE',
    this.bookingsCount = 0,
    this.matchesCount = 0,
    this.pointsCount = 0,
  });

  String get fullName => '$firstName $lastName'.trim().toUpperCase();

  /// Returns true if the user has PRO or ELITE tier subscription
  bool get isPro {
    final t = subscriptionTier.toUpperCase();
    return t == 'PRO' || t == 'ELITE';
  }

  /// Returns true if the user has ELITE tier subscription
  bool get isElite => subscriptionTier.toUpperCase() == 'ELITE';

  /// Returns the tier colour for badge / ring rendering
  String get tierColor {
    switch (subscriptionTier.toUpperCase()) {
      case 'ELITE':
        return '#FFB703';
      case 'PRO':
        return '#E100FF';
      case 'PLUS':
        return '#7F00FF';
      case 'CORE':
        return '#00A9FF';
      default:
        return '#9E9E9E';
    }
  }

  factory User.fromJson(Map<dynamic, dynamic> json) {
    // Traverse nested structures to find user fields
    Map<dynamic, dynamic> data = json;
    if (json.containsKey('data') && json['data'] is Map) {
      data = json['data'] as Map;
    }
    if (data.containsKey('user') && data['user'] is Map) {
      data = data['user'] as Map;
    }

    final profile = data['profile'] ?? {};
    final preferences = data['preferences'] ?? {};

    // Extract photo from various possible fields
    String? photo;
    if (data['profilePhotoUrl'] != null) {
      String url = data['profilePhotoUrl'].toString();
      photo = url.startsWith('http')
          ? url
          : '${ApiService.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
    } else if (data['profileImageUrl'] != null) {
      String url = data['profileImageUrl'].toString();
      photo = url.startsWith('http')
          ? url
          : '${ApiService.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
    } else if (data['photoUrl'] != null) {
      String url = data['photoUrl'].toString();
      photo = url.startsWith('http')
          ? url
          : '${ApiService.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
    } else if (data['images'] != null && (data['images'] as List).isNotEmpty) {
      final img = data['images'][0];
      if (img is Map && img['filePath'] != null) {
        photo =
            '${ApiService.baseUrl}/${img['filePath'].toString().replaceAll('\\', '/')}';
      } else if (img is String) {
        photo = img;
      }
    }

    // Extract photos list
    final List<String> photoUrls = [];
    final List<Map<String, String>> photoDetailsList = [];
    if (data['photos'] != null && data['photos'] is List) {
      for (var p in data['photos']) {
        String? urlStr = (p is Map)
            ? (p['url']?.toString() ?? p['filePath']?.toString())
            : null;
        if (urlStr != null) {
          String fullUrl = urlStr.startsWith('http')
              ? urlStr
              : '${ApiService.baseUrl}${urlStr.startsWith('/') ? '' : '/'}$urlStr';
          photoUrls.add(fullUrl);

          String id = p['id']?.toString() ?? p['_id']?.toString() ?? '';
          photoDetailsList.add({'id': id, 'url': fullUrl});
        }
      }
    }

    return User(
      id: data['id']?.toString() ?? data['_id']?.toString() ?? '',
      firstName: data['firstName'] ?? data['first_name'] ?? '',
      lastName: data['lastName'] ?? data['last_name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      profilePhoto:
          photo ??
          profile['profilePhoto'] ??
          data['profilePhoto'] ??
          data['avatar'],
      bio: profile['bio'] ?? data['bio'],
      city: profile['city'] ?? data['city'],
      gender: profile['gender'] ?? data['gender'],
      photos: photoUrls,
      photoDetails: photoDetailsList,
      age: data['age'] is int
          ? data['age']
          : int.tryParse(data['age']?.toString() ?? ''),
      displayName: profile['displayName'],
      occupation: profile['occupation'],
      company: profile['company'],
      education: profile['education'],
      lookingFor: profile['lookingFor'] is List
          ? List<String>.from(profile['lookingFor'].map((e) => e.toString()))
          : const [],
      interests: profile['interests'] is List
          ? List<String>.from(profile['interests'].map((e) => e.toString()))
          : const [],
      nightlifePreference: profile['nightlifePreference'] is List
          ? List<String>.from(
              profile['nightlifePreference'].map((e) => e.toString()),
            )
          : const [],
      musicPreference: preferences['musicPreference'] is List
          ? List<String>.from(
              preferences['musicPreference'].map((e) => e.toString()),
            )
          : const [],
      smokingPreference: preferences['smokingPreference']?.toString(),
      drinkPreference: preferences['drinkPreference'] is List
          ? List<String>.from(
              preferences['drinkPreference'].map((e) => e.toString()),
            )
          : const [],
      budgetRange: preferences['budgetRange']?.toString(),
      minBudget: preferences['minBudget'] != null
          ? int.tryParse(preferences['minBudget'].toString())
          : null,
      maxBudget: preferences['maxBudget'] != null
          ? int.tryParse(preferences['maxBudget'].toString())
          : null,
      preferredGenders: preferences['preferredGenders'] is List
          ? List<String>.from(
              preferences['preferredGenders'].map((e) => e.toString()),
            )
          : const [],
      minAgePreference: preferences['minAgePreference'] != null
          ? int.tryParse(preferences['minAgePreference'].toString())
          : null,
      maxAgePreference: preferences['maxAgePreference'] != null
          ? int.tryParse(preferences['maxAgePreference'].toString())
          : null,
      matchDistanceKm: preferences['matchDistanceKm'] != null
          ? int.tryParse(preferences['matchDistanceKm'].toString())
          : null,
      invisibleMode:
          preferences['invisibleMode'] == true || data['invisibleMode'] == true,
      showMeInMatching: preferences['showMeInMatching'] ?? true,
      bookingAlertsEnabled:
          preferences['bookingAlertsEnabled'] ??
          data['bookingAlertsEnabled'] ??
          true,
      dateOfBirth:
          profile['dateOfBirth']?.toString() ?? data['dateOfBirth']?.toString(),
      isVerified: data['isVerified'] == true,
      superLikesCount: json['superLikesCount'] != null
          ? int.tryParse(json['superLikesCount'].toString()) ?? 0
          : (data['superLikesCount'] != null
              ? int.tryParse(data['superLikesCount'].toString()) ?? 0
              : 0),
      plansCount: json['plansCount'] != null
          ? int.tryParse(json['plansCount'].toString()) ?? 0
          : (data['plansCount'] != null
              ? int.tryParse(data['plansCount'].toString()) ?? 0
              : 0),
      subscriptionTier: (data['subscriptionTier'] ?? json['subscriptionTier'] ?? 'FREE').toString(),
      bookingsCount: json['bookingsCount'] != null
          ? int.tryParse(json['bookingsCount'].toString()) ?? 0
          : (data['bookingsCount'] != null
              ? int.tryParse(data['bookingsCount'].toString()) ?? 0
              : 0),
      matchesCount: json['matchesCount'] != null
          ? int.tryParse(json['matchesCount'].toString()) ?? 0
          : (data['matchesCount'] != null
              ? int.tryParse(data['matchesCount'].toString()) ?? 0
              : 0),
      pointsCount: json['pointsCount'] != null
          ? int.tryParse(json['pointsCount'].toString()) ?? 0
          : (data['pointsCount'] != null
              ? int.tryParse(data['pointsCount'].toString()) ?? 0
              : 0),
    );
  }

  int calculateMatchWith(User other) {
    int percentage = 60;

    // 1. Compare Drink Preferences
    if (drinkPreference.isNotEmpty && other.drinkPreference.isNotEmpty) {
      bool drinkMatch = false;
      for (var drink in drinkPreference) {
        if (other.drinkPreference.any(
          (d) => d.toLowerCase().trim() == drink.toLowerCase().trim(),
        )) {
          drinkMatch = true;
          break;
        }
      }
      if (drinkMatch) {
        percentage += 10;
      }
    } else if (drinkPreference.isEmpty && other.drinkPreference.isEmpty) {
      percentage += 10;
    }

    // 2. Compare Smoking Preference
    if (smokingPreference != null && other.smokingPreference != null) {
      if (smokingPreference!.toLowerCase().trim() ==
          other.smokingPreference!.toLowerCase().trim()) {
        percentage += 10;
      }
    } else if (smokingPreference == null && other.smokingPreference == null) {
      percentage += 10;
    }

    // 3. Compare Hobbies / Interests
    if (interests.isNotEmpty && other.interests.isNotEmpty) {
      int commonInterests = 0;
      for (var interest in interests) {
        if (other.interests.any(
          (i) => i.toLowerCase().trim() == interest.toLowerCase().trim(),
        )) {
          commonInterests++;
        }
      }
      percentage += (commonInterests * 4).clamp(0, 12);
    }

    // 4. Compare Looking For
    if (lookingFor.isNotEmpty && other.lookingFor.isNotEmpty) {
      int commonLookingFor = 0;
      for (var lf in lookingFor) {
        if (other.lookingFor.any(
          (l) => l.toLowerCase().trim() == lf.toLowerCase().trim(),
        )) {
          commonLookingFor++;
        }
      }
      percentage += (commonLookingFor * 4).clamp(0, 8);
    }

    if (percentage > 100) {
      percentage = 100;
    }

    return percentage;
  }
}
