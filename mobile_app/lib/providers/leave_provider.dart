// mobile_app/lib/providers/leave_provider.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api/auth_api.dart';
import '../models/leave_request.dart';
import 'package:file_picker/file_picker.dart';

class LeaveProvider with ChangeNotifier {
  final AuthApi _authApi;
  List<LeaveRequest> _leaveRequests = [];
  bool _isLoading = false;
  String? _errorMessage;

  LeaveProvider(this._authApi);

  List<LeaveRequest> get leaveRequests => _leaveRequests;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // --- Fetch Leave Requests ---
  Future<void> fetchLeaveRequests() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _leaveRequests = await _authApi.getLeaveRequests();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Submit New Leave Request ---
  Future<void> submitLeaveRequest({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    FilePickerResult? document,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authApi.submitLeaveRequest(
        startDate: startDate,
        endDate: endDate,
        reason: reason,
        document: document,
      );
      _errorMessage = null; // Clear error on success
      await fetchLeaveRequests(); // Refresh the list after submission
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Update Leave Request Status (for Managers) ---
  Future<void> updateLeaveRequestStatus(int requestId, String status) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authApi.updateLeaveRequestStatus(requestId, status);
      _errorMessage = null;
      await fetchLeaveRequests(); // Refresh the list after update
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- View Document ---
  Future<String?> getDocumentUrl(int requestId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final url = await _authApi.getLeaveRequestDocumentUrl(requestId);
      return url;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}