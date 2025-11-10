import 'dart:convert';
import 'package:docapp/api/api_constant.dart';
import 'package:http/http.dart' as http;
import 'package:docapp/model/customer.dart' as model;

class customerApiService {
  final String baseUrl;
  final http.Client _client;

  customerApiService({
    this.baseUrl = ApiConstants.baseUrl, 
    http.Client? client,
  }) : _client = client ?? http.Client();

  // GET /api/CustomerDataM/GetAllAsync
  Future<List<model.Customer>> getCustomers() async {
    final uri = Uri.parse('$baseUrl/api/CustomerDataM/GetAllAsync');
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch customers (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);

    // Envelope per your sample: { StatusCode, Status, ErrorMessage, Response: [ ... ] }
    final list = _extractList(decoded);
    return list
        .map<model.Customer>((e) => model.Customer.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  // GET /api/CustomerDataM/GetAsync/{id}
  // Returns the "Response" object (map) for the given id.
  Future<Map<String, dynamic>> getCustomerDetailsMap(dynamic id) async {
    final uri = Uri.parse('$baseUrl/api/CustomerDataM/GetAsync/$id');
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch customer $id (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body);
    return _extractMap(decoded);
  }

  // Helpers for API envelopes

  List _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      // Support keys your server could use
      for (final k in ['Response', 'response', 'Data', 'data', 'result', 'items', 'value']) {
        final v = decoded[k];
        if (v is List) return v;
      }
    }
    return [];
  }

  Map<String, dynamic> _extractMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      // Response can be an object or an array with one object
      for (final k in ['Response', 'response', 'Data', 'data', 'result', 'value']) {
        final v = decoded[k];
        if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
        if (v is List && v.isNotEmpty && v.first is Map) {
          return Map<String, dynamic>.from(v.first as Map);
        }
      }
      return decoded;
    }
    return {};
  }
}