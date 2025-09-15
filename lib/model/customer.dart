import 'dart:typed_data';

class Customer {
  final String name;
  final String phone;
  final Uint8List? imageBytes;

  Customer({
    required this.name,
    required this.phone,
    this.imageBytes,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      name: map['name'],
      phone: map['phone'],
      imageBytes: map['imageBytes'] != null
          ? Uint8List.fromList(List<int>.from(map['imageBytes']))
          : null,
    );
  }
}

