// mobile_app/lib/providers/auth_provider.dart
import 'package:flutter/material.dart'; // Required for ChangeNotifier
import '../api/auth_api.dart';
import '../models/user.dart'; // Import your User model
import 'package:flutter/foundation.dart' show kIsWeb; // Required for kIsWeb
class AuthProvider with ChangeNotifier {
  User? _user; // Stores the currently logged-in user's data
  String? _token; // Stores the JWT token
  final AuthApi _authApi = AuthApi(); // Instance of your authentication API service
  String? _errorMessage; // Stores any error message from API calls or logic

  User? get user => _user; // Getter for the user object
  String? get token => _token; // Getter for the JWT token
  AuthApi get authApi => _authApi; // Expose AuthApi for other parts of the app if needed
  String? get errorMessage => _errorMessage; // Getter for error messages

  bool get isAuthenticated => _token != null; // Convenience getter for authentication status



  // --- Auto-Login (Check for existing token on app startup) ---
  Future<void> autoLogin() async {
    print('DEBUG: AuthProvider.autoLogin() called.');
    _errorMessage = null; // Clear any previous errors
    _token = await _authApi.getToken(); // Try to get a stored token
    if (_token != null) {
      print('DEBUG: AuthProvider.autoLogin() found token: ${_token!.substring(0,10)}...');
      try {
        // If a token exists, try to fetch user profile to confirm validity
        _user = await _authApi.fetchUserProfile(_token!); // Use fetchUserProfile
        print('DEBUG: AuthProvider.autoLogin() successfully fetched user profile for ${_user?.username}.');
        notifyListeners(); // Notify widgets that user is logged in
      } catch (e) {
        print('ERROR: AuthProvider.autoLogin() failed to fetch user profile: $e');
        _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Store error
        await logout(); // Token might be expired or invalid, log out
      }
    } else {
      print('DEBUG: AuthProvider.autoLogin() found no stored token.');
    }
  }

  // --- Manual Login ---
  Future<void> login(String username, String password) async {
    _token = await _authApi.login(username, password);
    if (_token != null) {
      _user = await _authApi.fetchUserProfile(_token!);
      notifyListeners();
    }
  }
  
  @override
  Future<void> logout() async {
    await _authApi.logout();
    _token = null;
    _user = null;
    notifyListeners();
  }
}