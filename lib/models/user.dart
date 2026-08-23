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
  final bool isLiked;
  final bool isSuperLiked;

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
    this.isLiked = false,
    this.isSuperLiked = false,
  });

  String get fullName {
    final String name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    if (displayName != null && displayName!.trim().isNotEmpty) return displayName!.trim();
    return '';
  }

  /// Returns true if the user has PRO or ELITE tier subscription
  bool get isPro {
    final t = subscriptionTier.toUpperCase();
    return t == 'PRO' || t == 'ELITE';
  }

  /// Returns true if the user has ELITE tier subscription
  bool get isElite => subscriptionTier.toUpperCase() == 'ELITE';

  /// Returns list of missing or incomplete profile field labels for the user
  List<String> get incompleteFields {
    final List<String> list = [];
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) list.add('Full Name');
    if (profilePhoto == null || profilePhoto!.trim().isEmpty) list.add('Profile Photo');
    if (bio == null || bio!.trim().isEmpty) list.add('Bio & About');
    if (gender == null || gender!.trim().isEmpty) list.add('Gender');
    if (city == null || city!.trim().isEmpty) list.add('City / Location');
    if (photos.isEmpty) list.add('Additional Photos');
    if (occupation == null || occupation!.trim().isEmpty) list.add('Occupation');
    if (interests.isEmpty) list.add('Interests');
    return list;
  }

  /// Calculates overall profile completion percentage (0 to 100)
  int get profileCompletionPercentage {
    int score = 0;
    if (firstName.trim().isNotEmpty && lastName.trim().isNotEmpty) score += 20;
    if (profilePhoto != null && profilePhoto!.trim().isNotEmpty) score += 20;
    if (bio != null && bio!.trim().isNotEmpty) score += 15;
    if (gender != null && gender!.trim().isNotEmpty) score += 15;
    if (city != null && city!.trim().isNotEmpty) score += 10;
    if (photos.isNotEmpty) score += 10;
    if (interests.isNotEmpty) score += 10;
    return score.clamp(0, 100);
  }

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

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    if (value is num) return value.toInt() == 1;
    return false;
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
    String? rawPhoto = (data['profilePhotoUrl'] ??
            data['profileImageUrl'] ??
            data['photoUrl'] ??
            data['profilePhoto'] ??
            data['photo'] ??
            data['image'] ??
            data['avatar'] ??
            data['userAvatar'] ??
            data['hostProfilePhotoUrl'] ??
            data['hostPhotoUrl'] ??
            data['senderImage'] ??
            data['senderPhoto'] ??
            data['imageUrl'])
        ?.toString();

    if (rawPhoto != null &&
        rawPhoto.trim().isNotEmpty &&
        rawPhoto != 'null' &&
        rawPhoto != 'undefined') {
      photo = rawPhoto.startsWith('http') || rawPhoto.startsWith('assets')
          ? rawPhoto
          : '${ApiService.baseUrl}${rawPhoto.startsWith('/') ? '' : '/'}$rawPhoto';
    } else if (data['images'] != null && (data['images'] as List).isNotEmpty) {
      final img = data['images'][0];
      if (img is Map && img['filePath'] != null) {
        photo =
            '${ApiService.baseUrl}/${img['filePath'].toString().replaceAll('\\', '/')}';
      } else if (img is String && img.isNotEmpty && img != 'null') {
        photo = img.startsWith('http') || img.startsWith('assets') ? img : '${ApiService.baseUrl}${img.startsWith('/') ? '' : '/'}$img';
      }
    }

    // Extract photos list
    final List<String> photoUrls = [];
    final List<Map<String, String>> photoDetailsList = [];
    if (data['photos'] != null && data['photos'] is List) {
      for (var p in data['photos']) {
        String? urlStr = (p is Map)
            ? (p['url']?.toString() ?? p['filePath']?.toString())
            : p?.toString();
        if (urlStr != null && urlStr.trim().isNotEmpty && urlStr != 'null') {
          String fullUrl = urlStr.startsWith('http') || urlStr.startsWith('assets')
              ? urlStr
              : '${ApiService.baseUrl}${urlStr.startsWith('/') ? '' : '/'}$urlStr';
          photoUrls.add(fullUrl);

          String id = (p is Map) ? (p['id']?.toString() ?? p['_id']?.toString() ?? '') : '';
          bool isPrimary = (p is Map && (p['isPrimary'] == true || p['isPrimary'] == 'true'));
          photoDetailsList.add({'id': id, 'url': fullUrl, 'isPrimary': isPrimary ? 'true' : 'false'});
        }
      }
    }

    if (photo == null && photoUrls.isNotEmpty) {
      photo = photoUrls.first;
    }
    // Extract minBudget & maxBudget with fallback to profile / data / budgetRange string
    int? parsedMinBudget = preferences['minBudget'] != null
        ? int.tryParse(preferences['minBudget'].toString())
        : (profile['minBudget'] != null
            ? int.tryParse(profile['minBudget'].toString())
            : (data['minBudget'] != null ? int.tryParse(data['minBudget'].toString()) : null));

    int? parsedMaxBudget = preferences['maxBudget'] != null
        ? int.tryParse(preferences['maxBudget'].toString())
        : (profile['maxBudget'] != null
            ? int.tryParse(profile['maxBudget'].toString())
            : (data['maxBudget'] != null ? int.tryParse(data['maxBudget'].toString()) : null));

    final rawBudgetRange = preferences['budgetRange']?.toString() ??
        profile['budgetRange']?.toString() ??
        data['budgetRange']?.toString();

    if ((parsedMinBudget == null || parsedMaxBudget == null) && rawBudgetRange != null) {
      final numbers = RegExp(r'\d+')
          .allMatches(rawBudgetRange)
          .map((m) => int.tryParse(m.group(0)!))
          .whereType<int>()
          .toList();
      if (numbers.length >= 2) {
        parsedMinBudget ??= numbers[0];
        parsedMaxBudget ??= numbers[1];
      } else if (numbers.length == 1) {
        if (rawBudgetRange.contains('Up to') || rawBudgetRange.contains('Under') || rawBudgetRange.contains('Max')) {
          parsedMaxBudget ??= numbers[0];
        } else {
          parsedMinBudget ??= numbers[0];
        }
      }
    }

    final rawPrefGenders = preferences['preferredGenders'] ?? profile['preferredGenders'] ?? data['preferredGenders'];
    final List<String> parsedPrefGenders = rawPrefGenders is List
        ? List<String>.from(rawPrefGenders.map((e) => e.toString()))
        : (rawPrefGenders is String && rawPrefGenders.isNotEmpty ? [rawPrefGenders] : const []);

    final rawDistance = preferences['matchDistanceKm'] ?? profile['matchDistanceKm'] ?? data['matchDistanceKm'];
    final int? parsedDistance = rawDistance != null ? int.tryParse(rawDistance.toString()) : null;

    final rawMinAge = preferences['minAgePreference'] ?? profile['minAgePreference'] ?? data['minAgePreference'];
    final int? parsedMinAge = rawMinAge != null ? int.tryParse(rawMinAge.toString()) : null;

    final rawMaxAge = preferences['maxAgePreference'] ?? profile['maxAgePreference'] ?? data['maxAgePreference'];
    final int? parsedMaxAge = rawMaxAge != null ? int.tryParse(rawMaxAge.toString()) : null;

    return User(
      id: data['id']?.toString() ?? data['_id']?.toString() ?? '',
      firstName: data['firstName'] ?? data['first_name'] ?? profile['firstName'] ?? profile['first_name'] ?? profile['displayName'] ?? data['displayName'] ?? data['name'] ?? '',
      lastName: data['lastName'] ?? data['last_name'] ?? profile['lastName'] ?? profile['last_name'] ?? '',
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
      budgetRange: rawBudgetRange,
      minBudget: parsedMinBudget,
      maxBudget: parsedMaxBudget,
      preferredGenders: parsedPrefGenders,
      minAgePreference: parsedMinAge,
      maxAgePreference: parsedMaxAge,
      matchDistanceKm: parsedDistance,
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
      isLiked: _parseBool(json['isLiked']) || _parseBool(data['isLiked']),
      isSuperLiked: _parseBool(json['isSuperLiked']) || _parseBool(data['isSuperLiked']),
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
