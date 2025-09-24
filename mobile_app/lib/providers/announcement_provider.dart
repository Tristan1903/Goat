import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/announcement_item.dart';
import '../models/role_item.dart';
import '../models/user_manual_section.dart'; // <--- Confirm this import is present

class AnnouncementProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;

  List<AnnouncementItem> _announcements = [];
  List<RoleItem> _allRoles = [];
  List<UserManualSection> _userManualSections = []; // <--- THIS MUST BE A LIST, AND INITIALIZED AS EMPTY LIST

  AnnouncementProvider(this._authApi);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<AnnouncementItem> get announcements => _announcements;
  List<RoleItem> get allRoles => _allRoles;
  List<UserManualSection> get userManualSections => _userManualSections;

  // --- Fetch All Announcements ---
  Future<void> fetchAnnouncements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _announcements = await _authApi.getAllAnnouncements();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchAnnouncements: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch All Roles (for target roles dropdown) ---
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

  // --- Add Announcement ---
  Future<void> addAnnouncement({
    required String title,
    required String message,
    String category = 'General',
    List<String>? targetRoleNames,
    String? actionLinkView,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.addAnnouncement(
        title: title,
        message: message,
        category: category,
        targetRoleNames: targetRoleNames,
        actionLinkView: actionLinkView,
      );
      _errorMessage = null;
      await fetchAnnouncements(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in addAnnouncement: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Delete Announcement ---
  Future<void> deleteAnnouncement(int announcementId, String title) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteAnnouncement(announcementId);
      _errorMessage = null;
      await fetchAnnouncements(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in deleteAnnouncement: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Clear All Announcements ---
  Future<void> clearAllAnnouncements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.clearAllAnnouncements();
      _errorMessage = null;
      await fetchAnnouncements(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in clearAllAnnouncements: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch User Manual Content ---
  Future<void> fetchUserManualContent() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _userManualSections = await _authApi.getUserManualContent(); // <--- This assigns a List
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchUserManualContent: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}