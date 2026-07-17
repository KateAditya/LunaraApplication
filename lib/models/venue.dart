import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VenueAmenities {
  final bool hasAC;
  final bool hasDJ;
  final bool hasPool;
  final bool hasWifi;
  final bool hasParking;
  final bool hasRooftop;
  final bool hasLiveMusic;
  final bool hasDanceFloor;
  final bool hasHappyHours;
  final bool hasVIPSection;
  final bool hasSmokingZone;
  final bool hasValetParking;
  final bool hasBottleService;
  final bool hasPrivateDining;
  final bool hasOutdoorSeating;

  VenueAmenities({
    this.hasAC = false,
    this.hasDJ = false,
    this.hasPool = false,
    this.hasWifi = false,
    this.hasParking = false,
    this.hasRooftop = false,
    this.hasLiveMusic = false,
    this.hasDanceFloor = false,
    this.hasHappyHours = false,
    this.hasVIPSection = false,
    this.hasSmokingZone = false,
    this.hasValetParking = false,
    this.hasBottleService = false,
    this.hasPrivateDining = false,
    this.hasOutdoorSeating = false,
  });

  factory VenueAmenities.fromJson(Map<dynamic, dynamic> json) {
    return VenueAmenities(
      hasAC: json['hasAC'] ?? false,
      hasDJ: json['hasDJ'] ?? false,
      hasPool: json['hasPool'] ?? false,
      hasWifi: json['hasWifi'] ?? false,
      hasParking: json['hasParking'] ?? false,
      hasRooftop: json['hasRooftop'] ?? false,
      hasLiveMusic: json['hasLiveMusic'] ?? false,
      hasDanceFloor: json['hasDanceFloor'] ?? false,
      hasHappyHours: json['hasHappyHours'] ?? false,
      hasVIPSection: json['hasVIPSection'] ?? false,
      hasSmokingZone: json['hasSmokingZone'] ?? false,
      hasValetParking: json['hasValetParking'] ?? false,
      hasBottleService: json['hasBottleService'] ?? false,
      hasPrivateDining: json['hasPrivateDining'] ?? false,
      hasOutdoorSeating: json['hasOutdoorSeating'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hasAC': hasAC,
      'hasDJ': hasDJ,
      'hasPool': hasPool,
      'hasWifi': hasWifi,
      'hasParking': hasParking,
      'hasRooftop': hasRooftop,
      'hasLiveMusic': hasLiveMusic,
      'hasDanceFloor': hasDanceFloor,
      'hasHappyHours': hasHappyHours,
      'hasVIPSection': hasVIPSection,
      'hasSmokingZone': hasSmokingZone,
      'hasValetParking': hasValetParking,
      'hasBottleService': hasBottleService,
      'hasPrivateDining': hasPrivateDining,
      'hasOutdoorSeating': hasOutdoorSeating,
    };
  }
}

class Venue {
  final String id;
  final String name;
  final String? category;
  final String addressLine1;
  final String? area;
  final String city;
  final double averageRating;
  final String? imageUrl;
  final bool featured;
  final String? type;
  final String? status;
  final double? latitude;
  final double? longitude;
  final List<dynamic>? images;
  final String? videoUrl;
  final VenueAmenities? amenities;
  final double? tableBookingCharges;
  final double? discountPercentage;
  final String? description;
  final String? openingTime;
  final String? closingTime;
  final List<dynamic>? daysOpen;
  final List<dynamic>? closedDates;
  final String? tagline;
  final double? coverChargeMale;
  final double? coverChargeFemale;
  final int? capacity;

  Venue({
    required this.id,
    required this.name,
    this.category,
    required this.addressLine1,
    this.area,
    required this.city,
    required this.averageRating,
    this.imageUrl,
    this.featured = false,
    this.type,
    this.status,
    this.latitude,
    this.longitude,
    this.images,
    this.videoUrl,
    this.amenities,
    this.tableBookingCharges,
    this.discountPercentage,
    this.description,
    this.openingTime,
    this.closingTime,
    this.daysOpen,
    this.closedDates,
    this.tagline,
    this.coverChargeMale,
    this.coverChargeFemale,
    this.capacity,
  });

  factory Venue.fromJson(Map<dynamic, dynamic> json) {
    String normalizeUrl(dynamic path) {
      if (path == null) return '';
      final pathStr = path.toString().trim();
      if (pathStr.isEmpty) return '';
      if (pathStr.startsWith('http://') || pathStr.startsWith('https://')) {
        return pathStr;
      }
      final cleanPath = pathStr.replaceAll('\\', '/');
      if (cleanPath.startsWith('/')) {
        return '${ApiService.baseUrl}$cleanPath';
      }
      return '${ApiService.baseUrl}/$cleanPath';
    }

    String? img;
    String? video;
    List<Map<dynamic, dynamic>> imageList = [];

    void addImage(String url, String type) {
      if (url.isEmpty) return;
      final exists = imageList.any((item) => item['url'] == url);
      if (!exists) {
        imageList.add({'url': url, 'type': type});
      }
    }

    // Parse new API coverImage
    if (json['coverImage'] != null && json['coverImage'] is Map) {
      final coverUrl = normalizeUrl(
        json['coverImage']['url'] ?? json['coverImage']['filePath'],
      );
      if (coverUrl.isNotEmpty) {
        img = coverUrl;
        addImage(coverUrl, 'interior');
      }
    }

    // Parse new API gallery
    if (json['gallery'] != null && json['gallery'] is List) {
      for (var item in json['gallery']) {
        if (item is Map) {
          final url = normalizeUrl(item['url'] ?? item['filePath']);
          addImage(url, 'interior');
        }
      }
    }

    // Parse new API menu (foodMenu, barMenu, beverageMenu)
    if (json['menu'] != null && json['menu'] is Map) {
      final menuMap = json['menu'] as Map;
      final menuKeys = ['foodMenu', 'barMenu', 'beverageMenu', 'partyPackages'];
      for (var key in menuKeys) {
        if (menuMap[key] != null && menuMap[key] is List) {
          for (var item in menuMap[key]) {
            if (item is Map) {
              final url = normalizeUrl(item['url'] ?? item['filePath']);
              addImage(url, key);
            }
          }
        }
      }
    }

    // Parse new API videos
    if (json['videos'] != null && json['videos'] is List) {
      for (var item in json['videos']) {
        if (item is Map) {
          final url = normalizeUrl(item['url'] ?? item['filePath']);
          if (url.isNotEmpty) {
            video ??= url;
            addImage(url, 'video');
          }
        }
      }
    }

    // Fallback: Parse old-format images
    if (imageList.isEmpty && json['images'] != null && json['images'] is List) {
      for (var image in json['images']) {
        if (image is Map) {
          final path = image['filePath'] as String?;
          final type = image['imageType']?.toString() ?? 'interior';
          if (path != null) {
            final url = normalizeUrl(path);
            addImage(url, type);
          }
        }
      }
      if (imageList.isNotEmpty && img == null) {
        img = imageList.first['url'];
      }
    }

    // Fallback: Parse single image fields
    if (img == null) {
      if (json['imageUrl'] != null) {
        img = normalizeUrl(json['imageUrl']);
      } else if (json['image'] != null) {
        img = normalizeUrl(json['image']);
      }
    }

    // Fallback: Parse single videoUrl field
    if (video == null && json['videoUrl'] != null) {
      video = normalizeUrl(json['videoUrl']);
    }

    return Venue(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      addressLine1: json['addressLine1'] ?? '',
      area: json['area'],
      city: json['city'] ?? '',
      averageRating:
          double.tryParse(json['averageRating']?.toString() ?? '0.0') ?? 0.0,
      imageUrl: img,
      featured: json['featured'] ?? false,
      type: json['category']?.toString().toUpperCase() ?? 'VENUE',
      status: json['status'],
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      images: imageList.isNotEmpty ? imageList : null,
      videoUrl: video,
      amenities: json['amenities'] != null
          ? VenueAmenities.fromJson(json['amenities'])
          : null,
      tableBookingCharges: double.tryParse(
        json['tableBookingCharges']?.toString() ?? '',
      ),
      discountPercentage: double.tryParse(
        json['discountPercentage']?.toString() ?? '',
      ),
      description: json['description'],
      openingTime: json['openingTime']?.toString(),
      closingTime: json['closingTime']?.toString(),
      daysOpen: json['daysOpen'] is List ? json['daysOpen'] as List : null,
      closedDates: json['closedDates'] is List ? json['closedDates'] as List : null,
      tagline: json['tagline']?.toString(),
      coverChargeMale: double.tryParse(
        json['coverChargeMale']?.toString() ?? '',
      ),
      coverChargeFemale: double.tryParse(
        json['coverChargeFemale']?.toString() ?? '',
      ),
      capacity: json['capacity'] != null
          ? int.tryParse(json['capacity'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'addressLine1': addressLine1,
      'area': area,
      'city': city,
      'averageRating': averageRating,
      'image': imageUrl,
      'images': images,
      'isAsset': false,
      'type': type,
      'status': status,
      'featured': featured,
      'latitude': latitude,
      'longitude': longitude,
      'videoUrl': videoUrl,
      'amenities': amenities?.toMap(),
      'tableBookingCharges': tableBookingCharges,
      'discountPercentage': discountPercentage,
      'description': description,
      'openingTime': openingTime,
      'closingTime': closingTime,
      'daysOpen': daysOpen,
      'closedDates': closedDates,
      'tagline': tagline,
      'coverChargeMale': coverChargeMale,
      'coverChargeFemale': coverChargeFemale,
      'capacity': capacity,
    };
  }

  bool isOpenAt(DateTime date, dynamic timeOpt) {
    TimeOfDay time;
    if (timeOpt is TimeOfDay) {
      time = timeOpt;
    } else if (timeOpt is String) {
      final parts = timeOpt.split(':');
      if (parts.length >= 2) {
        time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      } else {
        return true;
      }
    } else {
      return true;
    }
    return getInvalidReason(date, time) == null;
  }

  String? getInvalidReason(DateTime date, dynamic timeOpt) {
    TimeOfDay time;
    if (timeOpt is TimeOfDay) {
      time = timeOpt;
    } else if (timeOpt is String) {
      final parts = timeOpt.split(':');
      if (parts.length >= 2) {
        time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      } else {
        return null;
      }
    } else {
      return null;
    }

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    DateTime businessDate = dt;
    if (time.hour < 6) {
      businessDate = dt.subtract(const Duration(days: 1));
    }

    final yyyy = businessDate.year;
    final mm = businessDate.month.toString().padLeft(2, '0');
    final dd = businessDate.day.toString().padLeft(2, '0');
    final businessDateStr = '$yyyy-$mm-$dd';

    if (closedDates != null && closedDates!.isNotEmpty) {
      if (closedDates!.contains(businessDateStr)) {
        return 'The venue is closed on $businessDateStr (Holiday).';
      }
    }

    if (daysOpen != null && daysOpen!.isNotEmpty) {
      final weekdaysMap = {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      };
      final businessWeekdayName = weekdaysMap[businessDate.weekday];
      if (businessWeekdayName != null) {
        final isOpenOnWeekday = daysOpen!.any((d) {
          final str = d.toString().trim().toLowerCase();
          final fullDay = businessWeekdayName.toLowerCase();
          final shortDay = businessWeekdayName.substring(0, 3).toLowerCase();
          return str.contains(fullDay) || str.contains(shortDay);
        });

        if (!isOpenOnWeekday) {
          return 'The venue is not open on ${businessWeekdayName}s.';
        }
      }
    }

    if (openingTime != null && closingTime != null) {
      final openParts = openingTime!.split(':');
      final closeParts = closingTime!.split(':');
      if (openParts.length >= 2 && closeParts.length >= 2) {
        final openHour = int.tryParse(openParts[0]) ?? 0;
        final openMin = int.tryParse(openParts[1]) ?? 0;
        final closeHour = int.tryParse(closeParts[0]) ?? 0;
        final closeMin = int.tryParse(closeParts[1]) ?? 0;

        int openTimeMins = openHour * 60 + openMin;
        int closeTimeMins = closeHour * 60 + closeMin;
        if (closeTimeMins < openTimeMins) {
          closeTimeMins += 24 * 60;
        }

        int eventTimeMins = time.hour * 60 + time.minute;
        if (time.hour < 6 && closeTimeMins > 24 * 60) {
          eventTimeMins += 24 * 60;
        } else if (time.hour < openHour && closeTimeMins <= 24 * 60) {
          eventTimeMins -= 24 * 60;
        } else if (time.hour < 6 && time.hour >= closeHour) {
          eventTimeMins += 24 * 60;
        }

        if (eventTimeMins < openTimeMins || eventTimeMins >= closeTimeMins) {
          String formatTime(int h, int m) {
            final ampm = h >= 12 && h < 24 ? 'PM' : 'AM';
            final displayH = h % 12 == 0 ? 12 : h % 12;
            return '$displayH:${m.toString().padLeft(2, '0')} $ampm';
          }
          return 'Selected time is outside venue operating hours. The venue is open from ${formatTime(openHour, openMin)} to ${formatTime(closeHour, closeMin)}.';
        }
      }
    }

    return null; // Valid!
  }
}
