import 'dart:convert';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:docapp/model/customermodel.dart' as model;

class CustomerApiService {
  final baseUrl = ApiConstants.baseUrl;
  final http.Client _client;

  CustomerApiService({required http.Client? client})
    : _client = client ?? http.Client();

  Future<List<model.Customer>> getCustomers() async {
    final token = TokenStorage.getToken();
    final uri = Uri.parse('$baseUrl/api/customerDetails/GetAsync');

    final resp = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token', // if needed
      },
    );

    print(resp);

    if (resp.statusCode != 200) {
      throw Exception(
        'GET ${uri.path} failed: ${resp.statusCode} ${resp.body}',
      );
    }

    final decoded = json.decode(resp.body);
    if (decoded is! List) {
      throw Exception('Unexpected response type: ${decoded.runtimeType}');
    }

    final customers = decoded
        .map((e) => _mapApiToCustomer(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Deduplicate by phone (since sample contains duplicates)
    final seen = <String>{};
    final unique = <model.Customer>[];
    for (final c in customers) {
      if (seen.add(c.phone)) unique.add(c);
    }
    return unique;
  }

  model.Customer _mapApiToCustomer(Map<String, dynamic> m) {
    final fullName = (m['Name'] ?? '').toString().trim();
    final parts = fullName.isNotEmpty
        ? fullName.split(RegExp(r'\s+'))
        : <String>[];
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Map to your existing model.Customer.fromMap shape
    final mapForModel = <String, dynamic>{
      'name': first,
      'surname': last,
      'phone': (m['PhoneNo'] ?? '').toString(),
      'email': (m['Email'] ?? '').toString(),
      'address': (m['Address'] ?? '').toString(),
      'gender': (m['Gender'] ?? '').toString(),
      'others': m['Others'], // if supported
      'imageBytes': null,
    };

    return model.Customer.fromMap(mapForModel);
  }
}
