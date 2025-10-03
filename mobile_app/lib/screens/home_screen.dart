// mobile_app/lib/screens/home_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // For web links

// Imports for all screens that will be part of the navigation
import '../providers/auth_provider.dart';
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../models/navigation_item.dart'; // For AppScreenItem, AppNavigationCategory

// Inventory Screens
import 'location_list_screen.dart';
import 'submit_sales_screen.dart';
import 'submit_delivery_screen.dart';
import 'recipe_list_screen.dart';
import 'set_bod_stock_screens.dart';
import 'set_all_prices_screen.dart';
import 'manage_products_screen.dart';
import 'manage_locations_screen.dart';


// Scheduling & HR Screens
import 'my_schedule_screen.dart';
import 'submit_availability_screen.dart';
import 'leave_request_list_screen.dart';
import 'daily_shifts_screen.dart';
import 'consolidated_schedule_screen.dart';
import 'manage_swaps_screen.dart';
import 'manage_volunteered_shifts_screen.dart';
import 'manage_staff_minimums_screen.dart';
import 'manage_warnings_screen.dart';

// Admin & Operations Screens
import 'manage_bookings_screen.dart';
import 'manage_users_screen.dart';
import 'active_users_screen.dart';
import 'manage_announcements_screen.dart';
import 'user_manual_screen.dart';

// Reports Screens
import 'daily_summary_report_screen.dart';
import 'inventory_log_screen.dart';
import 'variance_report_screen.dart';
import 'historical_variance_chart_screen.dart';

// New screen for showing category details
import 'category_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  AppNavigationCategory? _selectedCategory; // The category currently selected/animated
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.3, 0.0)).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  } 

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openCategoryDetail(AppNavigationCategory category) async {
    setState(() {
      _selectedCategory = category;
    });
    await _controller.forward(); // Animate the main screen out
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FadeTransition(
          opacity: animation,
          child: CategoryDetailScreen(category: category),
        ),
      ),
    );
    _controller.reverse(); // Animate the main screen back in
    setState(() {
      _selectedCategory = null; // Clear selected category
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.user;
    final List<String> currentUserRoles = currentUser?.roles ?? [];

    // --- Define your main navigation categories here ---
    // Group all your screens into logical categories
    final List<AppNavigationCategory> categories = [
      AppNavigationCategory(
        title: 'Inventory Management',
        icon: Icons.inventory_2,
        backgroundColor: const Color.fromRGBO(71, 0, 22, 1), // Dark red/brown
        subScreens: [
          AppScreenItem(title: 'Locations Count', icon: Icons.map, targetScreen: const LocationListScreen(), requiredRoles: ['bartender', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Submit Sales', icon: Icons.point_of_sale, targetScreen: const SubmitSalesScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Log Delivery', icon: Icons.local_shipping, targetScreen: const SubmitDeliveryScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Recipe Book', icon: Icons.book, targetScreen: const RecipeListScreen(), requiredRoles: ['bartender', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Set BOD Stock', icon: Icons.inventory, targetScreen: const SetBodStockScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Set Prices', icon: Icons.sell, targetScreen: const SetAllPricesScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Products', icon: Icons.category, targetScreen: const ManageProductsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Locations', icon: Icons.location_on, targetScreen: const ManageLocationsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
        ],
      ),
      AppNavigationCategory(
        title: 'Staffing & HR',
        icon: Icons.people_alt,
        backgroundColor: const Color(0xFF1F2536), // Dark blue-grey
        subScreens: [
          AppScreenItem(title: 'Shifts for Today', icon: Icons.calendar_today, targetScreen: const DailyShiftsScreen(), requiredRoles: ['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Submit Availability', icon: Icons.event_available, targetScreen: const SubmitAvailabilityScreen(), requiredRoles: ['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Leave Requests', icon: Icons.calendar_month, targetScreen: const LeaveRequestListScreen(), requiredRoles: ['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'View BOH Schedule', icon: Icons.group, targetScreen: const ConsolidatedScheduleScreen(initialViewType: 'boh'), requiredRoles: ['bartender', 'skullers', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'View FOH Schedule', icon: Icons.group, targetScreen: const ConsolidatedScheduleScreen(initialViewType: 'foh'), requiredRoles: ['waiter', 'manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'View Managers Schedule', icon: Icons.manage_accounts, targetScreen: const ConsolidatedScheduleScreen(initialViewType: 'managers'), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Swaps', icon: Icons.swap_horiz, targetScreen: const ManageSwapsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Volunteered', icon: Icons.back_hand, targetScreen: const ManageVolunteeredShiftsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Min Staff', icon: Icons.group_work, targetScreen: const ManageStaffMinimumsScreen(initialRoleName: 'bartender', initialWeekOffset: 0), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Manage Warnings', icon: Icons.warning, targetScreen: const ManageWarningsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Temp Schedule Test (Web)', icon: Icons.calendar_view_day, targetScreen: const SizedBox.shrink(), webLinkPath: '/temp_schedule_test', webLinkBaseUrl: 'https://portal.goatandco.com', requiredRoles: ['manager', 'general_manager', 'system_admin']),
        ],
      ),
      AppNavigationCategory(
        title: 'Admin & Operations',
        icon: Icons.settings,
        backgroundColor: Theme.of(context).colorScheme.primary, // Using theme primary color
        subScreens: [
          AppScreenItem(title: 'Manage Bookings', icon: Icons.event_note, targetScreen: const ManageBookingsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin', 'hostess', 'owners']),
          AppScreenItem(title: 'Manage Users', icon: Icons.supervised_user_circle, targetScreen: const ManageUsersScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Active Users', icon: Icons.person_pin, targetScreen: const ActiveUsersScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin', 'owners']),
          AppScreenItem(title: 'Announcements', icon: Icons.campaign, targetScreen: const ManageAnnouncementsScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin', 'bartender', 'waiter', 'skullers']),
          AppScreenItem(title: 'Web Scheduler Tool', icon: Icons.calendar_month, targetScreen: const SizedBox.shrink(), webLinkPath: '/scheduler/bartenders', webLinkBaseUrl: 'https://abbadon1903.pythonanywhere.com', requiredRoles: ['scheduler', 'manager', 'general_manager', 'system_admin']),
        ],
      ),
      AppNavigationCategory(
        title: 'Reports',
        icon: Icons.analytics,
        backgroundColor: Colors.teal.shade700,
        subScreens: [
          AppScreenItem(title: 'Daily Summary', icon: Icons.summarize, targetScreen: const DailySummaryReportScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Inventory Log', icon: Icons.history, targetScreen: const InventoryLogScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Variance Report', icon: Icons.compare_arrows, targetScreen: const VarianceReportScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
          AppScreenItem(title: 'Historical Variance', icon: Icons.trending_up, targetScreen: const HistoricalVarianceChartScreen(), requiredRoles: ['manager', 'general_manager', 'system_admin']),
        ],
      ),
      AppNavigationCategory(
        title: 'User Manual',
        icon: Icons.menu_book,
        backgroundColor: Colors.blueGrey.shade700,
        subScreens: [
          AppScreenItem(title: 'View Manual', icon: Icons.book_outlined, targetScreen: const UserManualScreen(), requiredRoles: []),
        ],
      ),
    ];

    // Filter out categories that have no accessible sub-screens for the current user
    final List<AppNavigationCategory> accessibleCategories = categories
        .where((category) => category.subScreens.any(
            (item) => item.requiredRoles.isEmpty || currentUserRoles.any((r) => item.requiredRoles.contains(r)),
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: Color.fromRGBO(0, 71, 49, 1),
      appBar: AppBar(
        title: Text('Dashboard', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              authProvider.logout();
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Stack( // Use Stack for the animation
        children: [
          // Main content (category grid) - animates out
          SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AbsorbPointer( // Prevent interaction with background when detail screen is open
                absorbing: _selectedCategory != null,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // 2 categories per row
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                      childAspectRatio: 1.0, // Square cards
                    ),
                    itemCount: accessibleCategories.length,
                    itemBuilder: (context, index) {
                      final category = accessibleCategories[index];
                      return _buildCategoryCard(context, category);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build a single category card
  Widget _buildCategoryCard(BuildContext context, AppNavigationCategory category) {
    return GestureDetector(
      onTap: () => _openCategoryDetail(category),
      child: Card(
        elevation: 8,
        color: category.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.icon,
              size: 60,
              color: category.textColor,
            ),
            const SizedBox(height: 10),
            Text(
              category.title,
              style: GoogleFonts.openSans(
                color: category.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}