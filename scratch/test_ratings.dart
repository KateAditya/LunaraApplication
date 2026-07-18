import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const String apiKey = 'AIzaSyDfse8V1Zd7nNKDb6Gkr3HoU2VXuZkc114';
  final venues = [
    {'name': 'AURA BAR & KITCHEN', 'city': 'Pune'},
    {'name': 'Sash', 'city': 'Pune'},
    {'name': 'Echho', 'city': 'Pune'},
    {'name': 'Cafe Vanabella', 'city': 'Pune'},
  ];

  for (var v in venues) {
    final query = Uri.encodeComponent('${v['name']} ${v['city']}');
    final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$query&inputtype=textquery&fields=rating,user_ratings_total,place_id&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      print('Venue: ${v['name']} Status: ${response.statusCode}');
      print('Body: ${response.body}');
    } catch (e) {
      print('Error for ${v['name']}: $e');
    }
  }
}
