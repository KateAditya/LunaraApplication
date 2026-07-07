import 'package:flutter_test/flutter_test.dart';
import 'package:lunara_app/models/venue.dart';

void main() {
  group('Venue.fromJson parsing', () {
    test('successfully parses updated API response format', () {
      final json = {
        "id": "4eab3ca7-4e0f-4564-9e78-982b215997e6",
        "ownerId": "d0534087-dda6-44cc-a2d5-8d56d3a85714",
        "name": "TEST Saurabh",
        "slug": "test-saurabh",
        "tagline": "",
        "description": "A test venue description.",
        "category": "club",
        "tags": [],
        "addressLine1": "TEST ADD",
        "addressLine2": "",
        "area": "Hinjewad",
        "city": "Pune",
        "state": "Maharashtra",
        "postalCode": "41110151",
        "country": "India",
        "latitude": "18.592378",
        "longitude": "73.744692",
        "displayOrder": 0,
        "nearestLandmark": "",
        "directions": "",
        "phone": "",
        "mobile": "9889899898",
        "whatsapp": "",
        "email": "vishal.karpe@micraft.co.in",
        "website": "",
        "instagram": "",
        "facebook": "",
        "cpName": "Vishal Karpe",
        "cpDesignation": "",
        "cpMobile": "",
        "cpEmail": "",
        "altCpName": "",
        "altCpDesignation": "",
        "altCpMobile": "",
        "altCpEmail": "",
        "capacity": 999,
        "seatingCapacity": 999,
        "standingCapacity": null,
        "openingTime": "19:05:00",
        "closingTime": "07:05:00",
        "daysOpen": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        "ageLimit": 21,
        "coverChargeMale": null,
        "coverChargeFemale": null,
        "discountPercentage": "100.00",
        "tableBookingCharges": "1000.00",
        "dressCode": "",
        "cuisineTypes": [],
        "musicTypes": [],
        "amenities": {
          "hasAC": true,
          "hasDJ": false,
          "hasPool": true,
          "hasWifi": false,
          "hasParking": false,
          "hasRooftop": false,
          "hasLiveMusic": false,
          "hasDanceFloor": false,
          "hasHappyHours": false,
          "hasVIPSection": false,
          "hasSmokingZone": false,
          "hasValetParking": false,
          "hasBottleService": false,
          "hasPrivateDining": false,
          "hasOutdoorSeating": false
        },
        "panNumber": "",
        "gstNumber": "",
        "fssaiLicense": "",
        "liquorLicense": "",
        "fireSafetyCert": "",
        "tradeLicense": "",
        "bankAccountNumber": "",
        "bankIFSC": "",
        "bankName": "",
        "averageRating": "4.20",
        "totalReviews": 10,
        "status": "live",
        "coverImage": {
          "id": "e3c11876-f325-44de-b9b6-0f5e3220ee3f",
          "url": "/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173479_94f725aa0bce65b6.compressed.webp",
          "filePath": "uploads\\venues\\4eab3ca7-4e0f-4564-9e78-982b215997e6\\raw\\1779716173479_94f725aa0bce65b6.compressed.webp",
          "fileSize": 4124,
          "mimeType": "image/webp",
          "isPrimary": true,
          "displayOrder": 0,
          "caption": null,
          "uploadedAt": "2026-05-25T13:36:16.458Z"
        },
        "gallery": [
          {
            "id": "f6d86dcf-e247-4bee-9fe9-bfabf4125c7a",
            "url": "/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173480_3274cc25bb8a911c.compressed.webp",
            "filePath": "uploads\\venues\\4eab3ca7-4e0f-4564-9e78-982b215997e6\\raw\\1779716173480_3274cc25bb8a911c.compressed.webp",
            "fileSize": 179724,
            "mimeType": "image/webp",
            "isPrimary": false,
            "displayOrder": 1,
            "caption": null,
            "uploadedAt": "2026-05-25T13:36:16.812Z"
          }
        ],
        "menu": {
          "foodMenu": [
            {
              "id": "0eadf6b0-dd74-4147-94b2-f2e72a73b6a1",
              "url": "/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716174269_748eb6ebaf6b2bf6.compressed.webp",
              "filePath": "uploads\\venues\\4eab3ca7-4e0f-4564-9e78-982b215997e6\\raw\\1779716174269_748eb6ebaf6b2bf6.compressed.webp",
              "fileSize": 196598,
              "mimeType": "image/webp",
              "isPrimary": false,
              "displayOrder": 1,
              "caption": null,
              "uploadedAt": "2026-05-25T13:36:21.294Z"
            }
          ],
          "barMenu": [],
          "beverageMenu": []
        },
        "videos": [
          {
            "id": "1978b2a6-fc35-4e64-ae05-3390f2ae6bbf",
            "url": "/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173562_3e738b28da49dca9.mp4",
            "filePath": "uploads\\venues\\4eab3ca7-4e0f-4564-9e78-982b215997e6\\raw\\1779716173562_3e738b28da49dca9.mp4",
            "fileSize": 15062854,
            "mimeType": "video/mp4",
            "isPrimary": false,
            "displayOrder": 1,
            "caption": null,
            "uploadedAt": "2026-05-25T13:36:25.803Z"
          }
        ]
      };

      final venue = Venue.fromJson(json);

      expect(venue.id, '4eab3ca7-4e0f-4564-9e78-982b215997e6');
      expect(venue.name, 'TEST Saurabh');
      expect(venue.category, 'club');
      expect(venue.addressLine1, 'TEST ADD');
      expect(venue.area, 'Hinjewad');
      expect(venue.city, 'Pune');
      expect(venue.averageRating, 4.2);
      expect(venue.latitude, 18.592378);
      expect(venue.longitude, 73.744692);
      expect(venue.tableBookingCharges, 1000.0);
      expect(venue.discountPercentage, 100.0);
      expect(venue.openingTime, '19:05:00');
      expect(venue.closingTime, '07:05:00');
      expect(venue.daysOpen, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);

      // Verify amenities
      expect(venue.amenities?.hasAC, true);
      expect(venue.amenities?.hasDJ, false);
      expect(venue.amenities?.hasPool, true);

      // Verify imageUrl (cover image url)
      expect(venue.imageUrl, 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173479_94f725aa0bce65b6.compressed.webp');

      // Verify videoUrl
      expect(venue.videoUrl, 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173562_3e738b28da49dca9.mp4');

      // Verify images list mapping (includes cover image, gallery, menus, and videos with correct types)
      final images = venue.images;
      expect(images, isNotNull);
      expect(images!.length, 4);

      // Cover image
      expect(images[0]['url'], 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173479_94f725aa0bce65b6.compressed.webp');
      expect(images[0]['type'], 'interior');

      // Gallery image
      expect(images[1]['url'], 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173480_3274cc25bb8a911c.compressed.webp');
      expect(images[1]['type'], 'interior');

      // Menu image
      expect(images[2]['url'], 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716174269_748eb6ebaf6b2bf6.compressed.webp');
      expect(images[2]['type'], 'foodMenu');

      // Video url
      expect(images[3]['url'], 'http://103.224.247.35:9076/uploads/venues/4eab3ca7-4e0f-4564-9e78-982b215997e6/raw/1779716173562_3e738b28da49dca9.mp4');
      expect(images[3]['type'], 'video');
    });

    test('falls back correctly to old format images and videoUrl', () {
      final json = {
        "id": "4eab3ca7-4e0f-4564-9e78-982b215997e6",
        "name": "TEST Saurabh",
        "addressLine1": "TEST ADD",
        "city": "Pune",
        "averageRating": "4.50",
        "images": [
          {
            "filePath": "uploads\\venues\\old_interior.webp",
            "imageType": "interior"
          },
          {
            "filePath": "uploads\\venues\\old_menu.webp",
            "imageType": "menu"
          }
        ],
        "videoUrl": "uploads\\venues\\old_video.mp4"
      };

      final venue = Venue.fromJson(json);

      expect(venue.imageUrl, 'http://103.224.247.35:9076/uploads/venues/old_interior.webp');
      expect(venue.videoUrl, 'http://103.224.247.35:9076/uploads/venues/old_video.mp4');

      final images = venue.images;
      expect(images, isNotNull);
      expect(images!.length, 2);
      expect(images[0]['url'], 'http://103.224.247.35:9076/uploads/venues/old_interior.webp');
      expect(images[0]['type'], 'interior');
      expect(images[1]['url'], 'http://103.224.247.35:9076/uploads/venues/old_menu.webp');
      expect(images[1]['type'], 'menu');
    });
  });
}
