import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String apiKey = "2740MzgzNjc6MzU1NjI6bmFlTXpnRkdtamIyczRtRA=";

  Future<String?> generatePoster(String templateId, String title) async {
    final url = Uri.parse("https://rest.apitemplate.io/v2/create-image");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "X-API-KEY": apiKey,
      },
      body: jsonEncode({
        "template_id": templateId,
        "modifications": [
          {"name": "title", "text": title}, // your template variable name
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["download_url"]; // URL of generated poster
    } else {
      print("API Error: ${response.body}");
      return null;
    }
  }
}
