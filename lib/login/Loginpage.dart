import 'dart:convert';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/login/otpverficationpage.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final TextEditingController phoneController = TextEditingController();
  bool isLoading = false;
  String apiMessage = '';
  final bool isUser = true;

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  bool validatePhone(String phone) => RegExp(r'^\d{10}$').hasMatch(phone);

  Future<void> loginUser() async {
    final phone = phoneController.text.trim();

    if (!validatePhone(phone)) {
      setState(() => apiMessage = "Please enter a valid 10-digit phone number");
      return;
    }

    setState(() {
      isLoading = true;
      apiMessage = "";
    });

    try {
      final baseUrl = ApiConstants.baseUrl;
      final url = Uri.parse("$baseUrl/api/Auth/LoginV2");
      final body = {"MobileNumber": phone, "IsUser": isUser};

      final res = await http.post(
        url,
        headers: const {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(body),
      );

      debugPrint("👉 Login response: ${res.statusCode}");
      debugPrint("👉 Body: ${res.body}");

      if (!mounted) return;

      if (res.statusCode == 200) {
        Map<String, dynamic> data = {};
        try {
          data = jsonDecode(res.body) as Map<String, dynamic>;
        } catch (e) {
          debugPrint("⚠️ Failed to decode JSON: $e");
        }

        final token = _extractToken(data);
        if (token != null && token.isNotEmpty) {
          // Save the token (temporary or final; OTP page will overwrite if needed)
          await TokenStorage.saveToken(token);
        }

        final otpMessage = (data["Message"] ?? data["message"] ?? "").toString();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OTPVerificationView(
              mobileNumber: phone,
              otpMessage: otpMessage,
            ),
          ),
        );
        return;
      }

      String serverMsg = '';
      try {
        final m = jsonDecode(res.body);
        if (m is Map<String, dynamic>) {
          serverMsg = (m['Message'] ??
                  m['ErrorMessage'] ??
                  m['message'] ??
                  m['error'] ??
                  '')
              .toString();
        }
      } catch (_) {}

      setState(() {
        apiMessage = serverMsg.isNotEmpty
            ? serverMsg
            : "Server responded with ${res.statusCode}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => apiMessage = "❌ Error: $e");
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  String? _extractToken(Map<String, dynamic> data) {
    if (data["Response"] is String) return data["Response"];
    if (data["token"] is String) return data["token"];
    if (data["accessToken"] is String) return data["accessToken"];
    if (data["Token"] is String) return data["Token"];
    if (data["Response"] is Map) {
      final responseMap = data["Response"] as Map<String, dynamic>;
      if (responseMap["token"] is String) return responseMap["token"];
      if (responseMap["accessToken"] is String) return responseMap["accessToken"];
      if (responseMap["Token"] is String) return responseMap["Token"];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 140),
              SizedBox(
                height: 200,
                child: Center(
                  child: Image.asset('assets/images/Loginpage.png'),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Login',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your WhatsApp number to continue',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: InputDecoration(
                  counterText: '',
                  labelText: '10-digit WhatsApp number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (apiMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  apiMessage,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isLoading ? null : loginUser,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Login', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}