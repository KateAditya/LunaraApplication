import 'dart:convert';
import 'dart:io';
import '../lib/models/user.dart';

void main() async {
  final client = HttpClient();
  try {
    final userId = 'a975d1a2-78b7-482b-b941-8a72bcca9fc9';
    final profileReq = await client.getUrl(Uri.parse('http://103.224.247.35:9076/api/mobile/user/userprofile?userId=$userId'));
    final profileRes = await profileReq.close();
    final profileBody = await profileRes.transform(utf8.decoder).join();
    final profileData = jsonDecode(profileBody);
    
    // Call User.fromJson
    final user = User.fromJson(profileData);
    print('Parsed User successfully:');
    print('  ID: ${user.id}');
    print('  Name: ${user.fullName}');
    print('  ProfilePhoto: ${user.profilePhoto}');
    print('  Photos List: ${user.photos}');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
