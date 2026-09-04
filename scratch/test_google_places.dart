// ignore_for_file: avoid_print
import 'package:http/http.dart' as http;

Future<void> main() async {
  const String apiKey = 'AIzaSyDfse8V1Zd7nNKDb6Gkr3HoU2VXuZkc114';
  const String venueName = 'Diablo';
  const String city = 'Mumbai';

  final query = Uri.encodeComponent('$venueName $city');
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=$query&inputtype=textquery&fields=rating,user_ratings_total,place_id&key=$apiKey';

  try {
    print('Calling URL: $url');
    final response = await http.get(Uri.parse(url));
    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
