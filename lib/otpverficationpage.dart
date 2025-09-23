import 'dart:convert';
import 'package:docapp/api/api_constant.dart';
import 'package:docapp/dashboardpage.dart';
import 'package:docapp/storage/Token_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/route_manager.dart';
import 'package:http/http.dart' as http;
import 'package:pinput/pinput.dart';

class OTPVerificationView extends StatefulWidget {
  final String mobileNumber;
  final String otpMessage; // Message returned from login API

  const OTPVerificationView({
    super.key,
    required this.mobileNumber,
    required this.otpMessage,
  });

  @override
  State<OTPVerificationView> createState() => _OTPVerificationViewState();
}

class _OTPVerificationViewState extends State<OTPVerificationView> {
  final pinController = TextEditingController();
  bool isLoading = false;
  String apiMessage = '';

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  Future<void> verifyOtp() async {
    final otp = pinController.text.trim();
    if (otp.length != 6) {
      setState(() => apiMessage = "Please enter a 6-digit OTP.");
      return;
    }

    setState(() {
      isLoading = true;
      apiMessage = '';
    });

    try {
      final baseUrl = ApiConstants.baseUrl;
      final url = Uri.parse("$baseUrl/api/Auth/OtpVerification");

      // ✅ Get Login token saved earlier (from LoginV2)
      final loginToken = await TokenStorage.getToken();
      if (loginToken == null || loginToken.isEmpty) {
        setState(() =>
            apiMessage = "No session token found. Please login again.");
        return;
      }

      // ✅ Body exactly as API spec requires
      final body = {
        "Token": loginToken,
        "OTP": otp,
        "IsUser": true,
      };

      final res = await http.post(
        url,
        headers: const {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode(body),
      );

      debugPrint("👉 OTP Response ${res.statusCode}: ${res.body}");

      if (!mounted) return;

      final Map<String, dynamic> data =
          jsonDecode(res.body) as Map<String, dynamic>;

      final bool success =
          (res.statusCode == 200 && (data["Status"] == true));

      if (success) {

        final verifiedToken = _extractToken(data);
        if (verifiedToken != null && verifiedToken.isNotEmpty) {
          await TokenStorage.saveToken(verifiedToken);
          debugPrint("✅ Saved verified token: $verifiedToken");
        } else {
          // ✅ fallback keep login token
          await TokenStorage.saveToken(loginToken);
        }

      }
         if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => Dashboardpage()),
        (route) => false,
      );

      // ❌ Not successful → show message
      final errorMsg = (data["Message"] ??
              data["ErrorMessage"] ??
              data["Response"]?.toString() ??
              "OTP Verification failed")
          .toString();

      setState(() {
        apiMessage = errorMsg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => apiMessage = "❌ Error: $e");
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  /// Extract token from server response
  String? _extractToken(Map<String, dynamic> data) {
    if (data["Response"] is String) return data["Response"];
    if (data["token"] is String) return data["token"];
    if (data["accessToken"] is String) return data["accessToken"];
    if (data["Token"] is String) return data["Token"];
    if (data["Response"] is Map) {
      final r = Map<String, dynamic>.from(data["Response"]);
      if (r["token"] is String) return r["token"];
      if (r["Token"] is String) return r["Token"];
      if (r["accessToken"] is String) return r["accessToken"];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 50,
      height: 50,
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Verify OTP"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Get.back(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 80),
            Center(
              child: Image.asset("assets/images/verification.jpg", height: 180),
            ),
            const SizedBox(height: 20),
            Text(
              widget.otpMessage.isNotEmpty
                  ? widget.otpMessage
                  : "Enter the OTP sent to ${widget.mobileNumber}",
              style:
                  const TextStyle(fontSize: 16, color: Colors.blueGrey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Pinput(
              controller: pinController,
              length: 6,
              defaultPinTheme: defaultPinTheme,
              focusedPinTheme: defaultPinTheme.copyWith(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (apiMessage.isNotEmpty)
              Text(
                apiMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Verify"),
            ),
          ],
        ),
      ),
    );
  }
}