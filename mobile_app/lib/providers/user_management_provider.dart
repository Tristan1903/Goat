// mobile_app/lib/providers/user_management_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/user.dart';
import '../models/role_item.dart';

class UserManagementProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;

  List<User> _users = [];
  List<RoleItem> _allRoles = []; // All available roles for assignment/filtering

  // Filter state for users
  String? _selectedRoleFilter = 'all';
  String? _searchQuery = '';

  UserManagementProvider(this._authApi);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<User> get users => _users;
  List<RoleItem> get allRoles => _allRoles;

  // Getters for filter state
  String? get selectedRoleFilter => _selectedRoleFilter;
  String? get searchQuery => _searchQuery;

  // --- Filter Setters ---
  void setRoleFilter(String? roleName) {
    _selectedRoleFilter = roleName;
    fetchUsers();
  }
  void setSearchQuery(String? query) {
    _searchQuery = query;
    fetchUsers();
  }
  void clearFilters() {
    _selectedRoleFilter = 'all';
    _searchQuery = '';
    fetchUsers();
  }

  // --- Fetch All Users ---
  Future<void> fetchUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _users = await _authApi.getAllUsers(
        role: _selectedRoleFilter,
        search: _searchQuery,
      );
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchUsers: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch All Roles ---
  Future<void> fetchAllRoles() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _allRoles = await _authApi.getAllRoles();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchAllRoles: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Initial Data (Users and Roles) ---
  Future<void> fetchInitialUserManagementData() async {
    await Future.wait([
      fetchUsers(),
      fetchAllRoles(),
    ]);
  }

  // --- Fetch User Details ---
  Future<User?> getUserDetails(int userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final Map<String, dynamic> data = await _authApi.getUserDetails(userId);
      return User.fromJson(data);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in getUserDetails: $_errorMessage');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Add User ---
  Future<void> addUser({
    required String username,
    required String fullName,
    required String password,
    required List<String> roles,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.addUser(
        username: username,
        fullName: fullName,
        password: password,
        roles: roles,
      );
      _errorMessage = null;
      await fetchUsers(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in addUser: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Edit User Details ---
  Future<void> editUserDetails(int userId, {
    required String username,
    required String fullName,
    String? password,
    required List<String> roles,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.editUserDetails(
        userId,
        username: username,
        fullName: fullName,
        password: password,
        roles: roles,
      );
      _errorMessage = null;
      await fetchUsers(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in editUserDetails: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Suspend User ---
  Future<void> suspendUser(int userId, {
    DateTime? suspensionEndDate,
    bool deleteSuspensionDocument = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.suspendUser(
        userId,
        suspensionEndDate: suspensionEndDate,
        deleteSuspensionDocument: deleteSuspensionDocument,
      );
      _errorMessage = null;
      await fetchUsers(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in suspendUser: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Reinstate User ---
  Future<void> reinstateUser(int userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.reinstateUser(userId);
      _errorMessage = null;
      await fetchUsers(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in reinstateUser: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Delete User ---
  Future<void> deleteUser(int userId, String fullName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteUser(userId);
      _errorMessage = null;
      await fetchUsers(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in deleteUser: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Active Users Data ---
  List<User> _activeUsers = [];
  List<User> get activeUsers => _activeUsers;

  Future<void> fetchActiveUsersData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _activeUsers = await _authApi.getActiveUsersData();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchActiveUsersData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Force Logout User ---
  Future<void> forceLogoutUser(int userId, String fullName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.forceLogoutUser(userId);
      _errorMessage = null;
      await fetchActiveUsersData(); // Refresh active users list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in forceLogoutUser: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}