// mobile_app/lib/providers/hr_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/warning_item.dart';
import '../models/staff_member.dart'; // For staff/manager dropdowns

class HrProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;

  List<WarningItem> _warnings = [];
  List<StaffMember> _staffUsersForWarnings = []; // For dropdown filters/selection
  List<StaffMember> _managerUsersForWarnings = []; // For dropdown filters/selection

  // Filter state for warnings
  int? _selectedStaffFilterId;
  int? _selectedManagerFilterId;
  String? _selectedSeverityFilter = 'all';
  String? _selectedStatusFilter = 'all';

  HrProvider(this._authApi);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<WarningItem> get warnings => _warnings;
  List<StaffMember> get staffUsersForWarnings => _staffUsersForWarnings;
  List<StaffMember> get managerUsersForWarnings => _managerUsersForWarnings;

  // Getters for filter state
  int? get selectedStaffFilterId => _selectedStaffFilterId;
  int? get selectedManagerFilterId => _selectedManagerFilterId;
  String? get selectedSeverityFilter => _selectedSeverityFilter;
  String? get selectedStatusFilter => _selectedStatusFilter;

  // --- Filter Setters ---
  void setStaffFilter(int? id) {
    _selectedStaffFilterId = id;
    fetchWarnings();
  }
  void setManagerFilter(int? id) {
    _selectedManagerFilterId = id;
    fetchWarnings();
  }
  void setSeverityFilter(String? severity) {
    _selectedSeverityFilter = severity;
    fetchWarnings();
  }
  void setStatusFilter(String? status) {
    _selectedStatusFilter = status;
    fetchWarnings();
  }
  void clearFilters() {
    _selectedStaffFilterId = null;
    _selectedManagerFilterId = null;
    _selectedSeverityFilter = 'all';
    _selectedStatusFilter = 'all';
    fetchWarnings();
  }

  // --- Fetch All Warnings ---
  Future<void> fetchWarnings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _warnings = await _authApi.getAllWarnings(
        staffId: _selectedStaffFilterId,
        managerId: _selectedManagerFilterId,
        severity: _selectedSeverityFilter,
        status: _selectedStatusFilter,
      );
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchWarnings: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Staff and Managers for Dropdowns ---
  Future<void> fetchStaffAndManagersForDropdowns() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _staffUsersForWarnings = await _authApi.getStaffForWarnings();
      _managerUsersForWarnings = await _authApi.getManagersForWarnings();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchStaffAndManagersForDropdowns: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Warning Details ---
  Future<WarningItem?> getWarningDetails(int warningId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _authApi.getWarningDetails(warningId);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in getWarningDetails: $_errorMessage');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Add Warning ---
  Future<void> addWarning({
    required int userId,
    required DateTime dateIssued,
    required String reason,
    required String severity,
    String? notes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.addWarning(
        userId: userId,
        dateIssued: dateIssued,
        reason: reason,
        severity: severity,
        notes: notes,
      );
      _errorMessage = null;
      await fetchWarnings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in addWarning: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Edit Warning ---
  Future<void> editWarning(int warningId, {
    required int userId,
    required DateTime dateIssued,
    required String reason,
    required String severity,
    required String status,
    String? notes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.editWarning(
        warningId,
        userId: userId,
        dateIssued: dateIssued,
        reason: reason,
        severity: severity,
        status: status,
        notes: notes,
      );
      _errorMessage = null;
      await fetchWarnings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in editWarning: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Resolve Warning ---
  Future<void> resolveWarning(int warningId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.resolveWarning(warningId);
      _errorMessage = null;
      await fetchWarnings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in resolveWarning: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Delete Warning ---
  Future<void> deleteWarning(int warningId, String userName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteWarning(warningId);
      _errorMessage = null;
      await fetchWarnings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in deleteWarning: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}