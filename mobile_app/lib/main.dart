// mobile_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // For MultiProvider and ChangeNotifierProvider
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manage_announcements_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/leave_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/bookings_provider.dart';
import 'providers/user_management_provider.dart';
import 'providers/announcement_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'screens/not_found_screen.dart';





void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, AnnouncementProvider>(
          create: (context) => AnnouncementProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousAnnouncementProvider) =>
              AnnouncementProvider(authProvider.authApi),
        ),
        ChangeNotifierProxyProvider<AuthProvider, UserManagementProvider>(
          create: (context) => UserManagementProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousUserManagementProvider) =>
              UserManagementProvider(authProvider.authApi),
        ),
        ChangeNotifierProxyProvider<AuthProvider, BookingsProvider>(
          create: (context) => BookingsProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousBookingsProvider) =>
              BookingsProvider(authProvider.authApi),
        ),
        ChangeNotifierProxyProvider<AuthProvider, InventoryProvider>(
          create: (context) => InventoryProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousInventoryProvider) =>
              InventoryProvider(authProvider.authApi),
        ),
        ChangeNotifierProxyProvider<AuthProvider, DashboardProvider>(
          create: (context) => DashboardProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
            Provider.of<AuthProvider>(context, listen: false).user,
          ),
          update: (context, authProvider, previousDashboardProvider) =>
              DashboardProvider(authProvider.authApi, authProvider.user),
        ),
        ChangeNotifierProxyProvider<AuthProvider, LeaveProvider>(
          create: (context) => LeaveProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousLeaveProvider) =>
              LeaveProvider(authProvider.authApi),
        ),
        // <--- NEW PROVIDER: ScheduleProvider depends on AuthProvider's AuthApi
        ChangeNotifierProxyProvider<AuthProvider, ScheduleProvider>(
          create: (context) => ScheduleProvider(
            Provider.of<AuthProvider>(context, listen: false).authApi,
          ),
          update: (context, authProvider, previousScheduleProvider) =>
              ScheduleProvider(authProvider.authApi),
        ),
      ],
      child: const MyApp(), // Your main application widget
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _initAuth; // Future to hold the auto-login process

  @override
  void initState() {
    super.initState();
    _initAuth = Provider.of<AuthProvider>(context, listen: false).autoLogin();

  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Goat & Co. Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // --- NEW: Global Theme based on Portfolio Book CSS ---
        primarySwatch: Colors.blue, // A blue swatch now
        primaryColor: const Color(0xFF00abf0),     // Bright Blue (Main accent color)
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF00abf0),     // Bright Blue
          onPrimary: Colors.white,
          secondary: const Color(0xFF00abf0),    // Bright Blue (Accent)
          onSecondary: Colors.white,
          tertiary: const Color(0xFF213524),
          onTertiary: Colors.white,
          background: const Color.fromRGBO(0, 71, 49, 1),    // Dark Blue-Grey (Body Background)
          onBackground: Colors.white,            // White text on dark background
          surface: Colors.white,                // Card background (for pages)
          onSurface: const Color(0xFF333333),   // Dark text on light surfaces
          error: Colors.red.shade700,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: const Color.fromRGBO(0, 71, 49, 1), // Match body background

        // Typography (using Nunito)
        textTheme: GoogleFonts.nunitoTextTheme( // <--- NEW FONT
          Theme.of(context).textTheme.apply(
                bodyColor: Colors.white, // Default text color on scaffold background
                displayColor: Colors.white,
              ),
        ),
        // Adjust text theme for text on light surfaces (like cards/pages)
        cardColor: const Color.fromARGB(255, 88, 88, 88), // Default card background
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        ),

        dataTableTheme: DataTableThemeData( // White separators
          headingTextStyle: GoogleFonts.nunito(
            color: Colors.white, // White text for headings
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          dataTextStyle: GoogleFonts.nunito(
            color: const Color(0xFF333333), // Dark text for data on light rows
            fontSize: 12,
          ),
          columnSpacing: 12,
          horizontalMargin: 10,
          dataRowColor: MaterialStateProperty.resolveWith((states) => Colors.white), // Explicitly white rows
        ),
        // AppBar Theme
        appBarTheme: AppBarTheme(
          backgroundColor: const Color.fromRGBO(48, 12, 16, 1), // Bright Blue
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.nunito(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),

        // ElevatedButton Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00abf0), // Bright Blue
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),

        // OutlinedButton Theme
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00abf0),
            side: const BorderSide(color: Color(0xFF00abf0)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),

        // TextButton Theme
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00abf0),
            textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600),
          ),
        ),

        // Input Decoration Theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFCDCDCD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF00abf0), width: 2), // Bright Blue focus
          ),
          labelStyle: GoogleFonts.nunito(color: const Color(0xFF666666)),
          hintStyle: GoogleFonts.nunito(color: const Color(0xFFCDCDCD)),
          fillColor: Colors.white,
          filled: true,
        ),

        // Dropdown Menu Theme
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.white),
            shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            elevation: MaterialStatePropertyAll(4),
          ),
          textStyle: GoogleFonts.nunito(color: const Color(0xFF333333)),
        ),
        // --- END NEW ---
      ),
      home: FutureBuilder(
        future: _initAuth, // Wait for auto-login to complete
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // Once auto-login is done, check authentication status
            return Consumer<AuthProvider>(
              builder: (context, auth, _) {
                // Navigate to HomeScreen if authenticated, otherwise LoginScreen
                return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
              },
            );
          }
          // Show a loading indicator while auto-login is in progress
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );

          
        },
        
      ),
      onUnknownRoute: (RouteSettings settings) {
        return MaterialPageRoute(builder: (context) => const NotFoundScreen());
      },
    );
  }
}