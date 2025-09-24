// mobile_app/lib/providers/auth_provider.dart
import 'package:flutter/material.dart'; // Required for ChangeNotifier
import '../api/auth_api.dart';
import '../models/user.dart'; // Import your User model
import 'package:firebase_messaging/firebase_messaging.dart'; // Required for FirebaseMessaging.instance.getToken()
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
    print('DEBUG: AuthProvider.login() called for $username.');
    _errorMessage = null; // Clear any previous errors
    try {
      _token = await _authApi.login(username, password); // Call API login
      if (_token != null) {
        print('DEBUG: AuthProvider.login() successfully got token: ${_token!.substring(0,10)}...');
        // After successful login, fetch the full user profile
        _user = await _authApi.fetchUserProfile(_token!);
        print('DEBUG: AuthProvider.login() successfully fetched user profile for ${_user?.username}.');
        notifyListeners(); // Notify widgets that user is logged in
      }
    } catch (e) {
      print('ERROR: AuthProvider.login() failed: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Store error
      notifyListeners(); // Notify UI about the error
    }
  }

  // --- NEW: Register FCM Token ---
  Future<void> registerFCMToken(String fcmToken, {String? deviceInfo}) async {
    print('DEBUG: AuthProvider.registerFCMToken() called with token: ${fcmToken.substring(0,10)}...');
    _errorMessage = null; // Clear any previous error message from API calls
    try {
      // Make sure this is only called when we intend to use FCM (i.e., for PWA)
      await _authApi.registerFCMToken(fcmToken, deviceInfo: deviceInfo);
      print('DEBUG: FCM token registered successfully with backend.');
    } catch (e) {
      print('ERROR: AuthProvider.registerFCMToken() failed: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Store error
      // You might want to retry or alert the user in a more visible way
    }
  }

  // --- NEW: Unregister FCM Token ---
  Future<void> unregisterFCMToken(String fcmToken) async {
    print('DEBUG: AuthProvider.unregisterFCMToken() called with token: ${fcmToken.substring(0,10)}...');
    _errorMessage = null; // Clear any previous error
    try {
      await _authApi.unregisterFCMToken(fcmToken);
      print('DEBUG: FCM token unregistered successfully from backend.');
    } catch (e) {
      print('ERROR: AuthProvider.unregisterFCMToken() failed: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Store error
    }
  }

  // --- MODIFIED: Logout to unregister FCM token and clear local state ---
  @override
  Future<void> logout() async {
    print('DEBUG: AuthProvider.logout() called.');
    _errorMessage = null; // Clear any errors before starting logout

    String? currentFCMToken;
    // --- NEW: Only try to get FCM token if on web (for PWA) ---
    if (kIsWeb) {
      try {
        currentFCMToken = await FirebaseMessaging.instance.getToken();
        print('DEBUG: AuthProvider.logout() retrieved FCM token for web: ${currentFCMToken?.substring(0,10)}...');
      } catch (e) {
        print('ERROR: AuthProvider.logout() failed to get FCM token: $e');
        // Do not crash logout process for this.
      }
    }
    // --- END NEW ---

    if (currentFCMToken != null) {
      // Attempt to unregister token from backend
      await unregisterFCMToken(currentFCMToken);
    }
    
    // Clear local JWT token from secure storage
    try {
      await _authApi.logout(); // This calls _storage.delete(key: 'jwt_token')
      print('DEBUG: AuthProvider.logout() (secure storage deletion) completed.');
    } catch (e) {
      print('ERROR: AuthProvider.logout() (secure storage deletion) failed: $e');
      _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Store error
      notifyListeners(); // Notify listeners of error, if needed
      return; // Exit if deletion failed critically
    }
    
    // Clear local authentication state
    _token = null;
    _user = null;
    print('DEBUG: AuthProvider.logout() cleared local token and user. Calling notifyListeners().');
    notifyListeners(); // This should trigger UI update (navigation to LoginScreen)
    print('DEBUG: AuthProvider.logout() process finished.');
  }
}