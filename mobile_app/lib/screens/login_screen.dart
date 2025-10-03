// mobile_app/lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // For accessing AuthProvider
import '../providers/auth_provider.dart'; // Import your AuthProvider
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(); // Controller for username input
  final _passwordController = TextEditingController(); // Controller for password input
  bool _isLoading = false; // To show loading spinner during login
  String? _errorMessage; // To display error messages
  bool _showPassword = false; // To toggle password visibility

  Future<void> _login() async {
    // Basic input validation
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = "Please enter both username and password.";
      });
      return;
    }

    setState(() {
      _isLoading = true; // Start loading state
      _errorMessage = null; // Clear previous errors
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.login(
        _usernameController.text,
        _passwordController.text,
      );
      // If login is successful, AuthProvider will notify listeners,
      // and main.dart (or a listener) will navigate to HomeScreen.
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', ''); // Clean up 'Exception: ' prefix
      });
    } finally {
      setState(() {
        _isLoading = false; // End loading state
      });
    }
  }

  @override
  void dispose() {
    // Clean up controllers when the widget is removed from the tree
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
    return Scaffold(
      // Use the dark background color from the new theme
      backgroundColor: const Color.fromRGBO(0, 71, 49, 1), // Dark Blue-Grey
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400, // Max width for login card
            ),
            child: Card(
              color: const Color.fromRGBO(48, 12, 16, 1), // Slightly lighter dark blue-grey for the login card (custom for this screen)
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Image.asset(
                      'assets/logo.png',
                      height: 120,
                      width: 120,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome Back',
                      style: GoogleFonts.nunito( // <--- NEW FONT
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to continue',
                      style: GoogleFonts.nunito( // <--- NEW FONT
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: GoogleFonts.nunito(color: Colors.white70), // <--- NEW FONT
                              filled: true,
                              fillColor: const Color(0xFF334455), // Custom input field background
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.transparent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF00abf0), width: 2), // Bright blue focus
                              ),
                            ),
                            style: GoogleFonts.nunito(color: Colors.white), // <--- NEW FONT
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your username.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: GoogleFonts.nunito(color: Colors.white70), // <--- NEW FONT
                              filled: true,
                              fillColor: const Color(0xFF334455), // Custom input field background
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Colors.transparent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF00abf0), width: 2), // Bright blue focus
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showPassword = !_showPassword;
                                  });
                                },
                              ),
                            ),
                            style: GoogleFonts.nunito(color: Colors.white), // <--- NEW FONT
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          if (_errorMessage != null)
                            Text(
                              _errorMessage!,
                              style: GoogleFonts.nunito(color: Colors.red, fontSize: 14), // <--- NEW FONT
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 16),
                          _isLoading
                              ? const CircularProgressIndicator(color: Color(0xFF00abf0)) // Bright blue loading indicator
                              : ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00abf0), // Bright blue submit button
                                    foregroundColor: Colors.white, // White text
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 18), // <--- NEW FONT
                                  ),
                                  child: const Text('LOG IN'),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}