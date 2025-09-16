import 'package:shared_preferences/shared_preferences.dart';

class OtpStorage {
  static Future<void> saveOtp(String otp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('otp', otp); // Store OTP correctly
  }

  static Future<String?> getOtp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('otp'); // Retrieve OTP
  }

  static Future<void> clearOtp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('otp'); // Clear OTP when needed
  }
}
