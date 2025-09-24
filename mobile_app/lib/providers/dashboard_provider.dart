// mobile_app/lib/providers/dashboard_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart'; // Still using AuthApi for calls
import '../models/announcement.dart';
import '../models/location.dart'; // For location statuses on dashboard
import '../models/user.dart'; // For current user roles

class DashboardProvider with ChangeNotifier {
  final AuthApi _authApi;
  final User? _currentUser; // Needed to filter dashboard views by role

  List<Announcement> _announcements = [];
  List<Location> _locationCountStatuses = []; // Locations with their current count status
  bool _bodSubmittedForToday = false; // Status if BOD has been done
  Map<String, dynamic> _dashboardSummary = {}; // For password resets, variances etc.
  bool _isLoading = false;
  String? _errorMessage;

  DashboardProvider(this._authApi, this._currentUser); // Inject AuthApi and current User

  List<Announcement> get announcements => _announcements;
  List<Location> get locationCountStatuses => _locationCountStatuses;
  bool get bodSubmittedForToday => _bodSubmittedForToday;
  Map<String, dynamic> get dashboardSummary => _dashboardSummary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // --- Fetch Announcements ---
  Future<void> fetchAnnouncements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final List<Map<String, dynamic>> data = await _authApi.getAnnouncements();
      _announcements = data.map((json) => Announcement.fromJson(json)).toList();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Location Count Statuses ---
  Future<void> fetchLocationCountStatuses() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final Map<String, dynamic> data = await _authApi.getLocationCountStatuses();
      _bodSubmittedForToday = data['bod_submitted_for_today'] as bool;
      _locationCountStatuses = (data['location_statuses'] as List<dynamic>)
          .map((json) => Location.fromJson(json)) // Reusing Location model but it now has 'status'
          .toList();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Dashboard Summary (Combined Alerts) ---
  Future<void> fetchDashboardSummary() async {
    // Only fetch if current user has roles that view this summary
    final userRoles = _currentUser?.roles ?? [];
    final bool canViewSummary = userRoles.any((role) =>
        ['manager', 'general_manager', 'system_admin', 'owners'].contains(role));

    if (!canViewSummary) {
      _dashboardSummary = {}; // Clear if user can't see it
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _dashboardSummary = await _authApi.getDashboardSummary();
      // Further process _dashboardSummary if needed, e.g., to map specific lists to models
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Combined Fetch for Dashboard ---
  Future<void> fetchAllDashboardData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    print('DEBUG: DashboardProvider fetching all data...');
    try {
        await Future.wait([
            fetchAnnouncements().then((_) => print('DEBUG: Announcements fetched.')),
            fetchLocationCountStatuses().then((_) => print('DEBUG: Location statuses fetched.')),
            fetchDashboardSummary().then((_) => print('DEBUG: Dashboard summary fetched.')),
        ]);
    } catch (e) {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        print('ERROR: Dashboard data fetch failed: $_errorMessage');
    } finally {
        _isLoading = false;
        notifyListeners();
    }
  }
}