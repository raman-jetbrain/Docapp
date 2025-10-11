import 'dart:convert';
import 'package:docapp/api/customer_api_service.dart';
import 'package:docapp/documentspage.dart';
import 'package:docapp/model/customer.dart' as model;
import 'package:flutter/material.dart';

class DocumentsPageLoader extends StatelessWidget {
  final String? phone;
  final String? id;

  const DocumentsPageLoader({super.key, this.phone, this.id})
      : assert(phone != null || id != null, 'Provide either phone or id');

  @override
  Widget build(BuildContext context) {
    final api = CustomerApiService();

    Future<model.Customer?> load() async {
      model.Customer? c;
      if (phone != null) {
        c = await api.getCustomerByPhone(phone!);
      } else if (id != null) {
        c = await api.getCustomerById(id!);
      }
      if (c == null) return null;

      // Hydrate image if needed
      final needsImage = (c.imageBytes == null || c.imageBytes!.isEmpty) && c.fileId != null;
      if (needsImage) {
        final bytes = await api.fetchFileBytesById(c.fileId);
        if (bytes != null && bytes.isNotEmpty) {
          try {
            c = c.copyWith(imageBytes: bytes, imageB64: base64Encode(bytes));
          } catch (_) {
            print("it not work");
          }
        }
      }
      return c;
    }

    return FutureBuilder<model.Customer?>(
      future: load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final c = snap.data;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Documents')),
            body: const Center(child: Text('Customer not found')),
          );
        }
        return DocumentsPage(customer: c);
      },
    );
  }
}