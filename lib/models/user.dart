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
  final bool bookingAlertsEnabled;
  final String? dateOfBirth;
  final bool isVerified;


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
    this.bookingAlertsEnabled = true,
    this.dateOfBirth,
    this.isVerified = false,
  });

  String get fullName => '$firstName $lastName';

  factory User.fromJson(Map<String, dynamic> json) {
    // Traverse nested structures to find user fields
    Map<String, dynamic> data = json;
    if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
      data = json['data'];
    }
    if (data.containsKey('user') && data['user'] is Map<String, dynamic>) {
      data = data['user'];
    }

    final profile = data['profile'] ?? {};
    final preferences = data['preferences'] ?? {};
    
    // Extract photo from various possible fields
    String? photo;
    if (data['profilePhotoUrl'] != null) {
      String url = data['profilePhotoUrl'].toString();
      photo = url.startsWith('http') ? url : 'http://103.224.247.35:9076${url.startsWith('/') ? '' : '/'}$url';
    } else if (data['profileImageUrl'] != null) {
      String url = data['profileImageUrl'].toString();
      photo = url.startsWith('http') ? url : 'http://103.224.247.35:9076${url.startsWith('/') ? '' : '/'}$url';
    } else if (data['images'] != null && (data['images'] as List).isNotEmpty) {
      final img = data['images'][0];
      if (img is Map && img['filePath'] != null) {
        photo = 'http://103.224.247.35:9076/${img['filePath'].toString().replaceAll('\\', '/')}';
      } else if (img is String) {
        photo = img;
      }
    }

    // Extract photos list
    final List<String> photoUrls = [];
    final List<Map<String, String>> photoDetailsList = [];
    if (data['photos'] != null && data['photos'] is List) {
      for (var p in data['photos']) {
        String? urlStr = (p is Map) ? (p['url']?.toString() ?? p['filePath']?.toString()) : null;
        if (urlStr != null) {
          String fullUrl = urlStr.startsWith('http') ? urlStr : 'http://103.224.247.35:9076${urlStr.startsWith('/') ? '' : '/'}$urlStr';
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
      profilePhoto: photo ?? profile['profilePhoto'] ?? data['profilePhoto'] ?? data['avatar'],
      bio: profile['bio'] ?? data['bio'],
      city: profile['city'] ?? data['city'],
      gender: profile['gender'] ?? data['gender'],
      photos: photoUrls,
      photoDetails: photoDetailsList,
      age: data['age'] is int ? data['age'] : int.tryParse(data['age']?.toString() ?? ''),
      displayName: profile['displayName'],
      occupation: profile['occupation'],
      company: profile['company'],
      education: profile['education'],
      lookingFor: profile['lookingFor'] is List ? List<String>.from(profile['lookingFor'].map((e) => e.toString())) : const [],
      interests: profile['interests'] is List ? List<String>.from(profile['interests'].map((e) => e.toString())) : const [],
      nightlifePreference: profile['nightlifePreference'] is List ? List<String>.from(profile['nightlifePreference'].map((e) => e.toString())) : const [],
      musicPreference: preferences['musicPreference'] is List ? List<String>.from(preferences['musicPreference'].map((e) => e.toString())) : const [],
      smokingPreference: preferences['smokingPreference']?.toString(),
      drinkPreference: preferences['drinkPreference'] is List ? List<String>.from(preferences['drinkPreference'].map((e) => e.toString())) : const [],
      budgetRange: preferences['budgetRange']?.toString(),
      minBudget: preferences['minBudget'] != null ? int.tryParse(preferences['minBudget'].toString()) : null,
      maxBudget: preferences['maxBudget'] != null ? int.tryParse(preferences['maxBudget'].toString()) : null,
      preferredGenders: preferences['preferredGenders'] is List ? List<String>.from(preferences['preferredGenders'].map((e) => e.toString())) : const [],
      minAgePreference: preferences['minAgePreference'] != null ? int.tryParse(preferences['minAgePreference'].toString()) : null,
      maxAgePreference: preferences['maxAgePreference'] != null ? int.tryParse(preferences['maxAgePreference'].toString()) : null,
      matchDistanceKm: preferences['matchDistanceKm'] != null ? int.tryParse(preferences['matchDistanceKm'].toString()) : null,
      invisibleMode: preferences['invisibleMode'] == true || data['invisibleMode'] == true,
      bookingAlertsEnabled: preferences['bookingAlertsEnabled'] ?? data['bookingAlertsEnabled'] ?? true,
      dateOfBirth: profile['dateOfBirth']?.toString() ?? data['dateOfBirth']?.toString(),
      isVerified: data['isVerified'] == true,
    );
  }
}
