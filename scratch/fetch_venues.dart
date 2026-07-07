import 'dart:convert';
import 'dart:io';

void main() async {
  final res = await HttpClient()
      .getUrl(Uri.parse('http://103.224.247.35:9076/api/venues'))
      .then((req) => req.close());
  final body = await res.transform(utf8.decoder).join();
  final data = jsonDecode(body);
  for (var v in data['venues']) {
    print('Venue: ${v['name']} - Lat: ${v['latitude']} - Lng: ${v['longitude']}');
  }
}
