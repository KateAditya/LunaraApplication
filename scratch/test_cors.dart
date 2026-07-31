import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> main() async {
  const String apiKey = 'AIzaSyDfse8V1Zd7nNKDb6Gkr3HoU2VXuZkc114';
  const String venueName = 'Diablo';
  const String city = 'Mumbai';

  final query = Uri.encodeComponent('$venueName $city');
  final rawUrl = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$query&inputtype=textquery&fields=rating,user_ratings_total,place_id&key=$apiKey';

  final proxyUrl = 'https://api.allorigins.win/get?url=${Uri.encodeComponent(rawUrl)}';
  try {
    print('Calling AllOrigins: $proxyUrl');
    final response = await http.get(Uri.parse(proxyUrl));
    print('Response status: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String contentsStr = data['contents'];
      print('Contents decoded: $contentsStr');
      final contents = json.decode(contentsStr);
      if (contents['status'] == 'OK' && contents['candidates'] != null && (contents['candidates'] as List).isNotEmpty) {
        print('SUCCESS! Candidate: ${contents['candidates'][0]}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
