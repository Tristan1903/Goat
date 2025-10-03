// mobile_app/lib/providers/schedule_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/schedule.dart'; // ScheduleItem and ShiftDefinitions
import '../models/staff_member.dart'; // <--- NEW IMPORT for SchedulerUser
import '../models/shift_management.dart';



class ScheduleProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;
  List<StaffMember> _staffForSwaps = [];

  // Availability Submission State
  Map<String, dynamic> _availabilityWindowStatus = {}; // {is_open, start_time_utc, end_time_utc}
  Map<String, List<String>> _myAvailability = {};
  List<DateTime> _availabilitySubmissionWeekDates = [];

  // Consolidated Schedule View State
  Map<String, dynamic> _consolidatedScheduleData = {}; // Raw data
  List<SchedulerUser> _usersInCategory = []; // Users for the current consolidated view
  String _currentConsolidatedViewType = 'boh'; // Default view type (boh, foh, managers)
  int _currentConsolidatedWeekOffset = 0;

  // --- NEW: Scheduler Role View State ---
  String? _currentSchedulerRole;
  int _currentSchedulerWeekOffset = 0;
  Map<String, dynamic>? _currentSchedulerData; // Holds users, availability, assignments, status

  // Manage Swaps State
  List<PendingSwap> _pendingSwaps = []; // Actionable pending swaps
  List<SwapHistoryItem> _swapHistory = []; // All swap requests history
  int _manageSwapsWeekOffset = 0;

  // Manage Volunteered Shifts State
  List<VolunteeredShiftItem> _actionableVolunteeredShifts = [];
  List<VolunteeredShiftHistoryItem> _volunteeredShiftHistory = [];
  int _manageVolunteeredWeekOffset = 0;

  // Manage Required Staff State
  List<RequiredStaffItem> _requiredStaff = [];
  String _manageRequiredStaffRole = 'bartender';
  int _manageRequiredStaffWeekOffset = 0;

  // Daily Shifts View State
  CategorizedDailyShifts? _dailyShiftsToday;
  

  // My Schedule View State
  Map<String, dynamic> _myAssignedScheduleData = {}; // Raw data from API
  List<DateTime> _myScheduleWeekDates = [];
  Map<String, List<ScheduleItem>> _myScheduleByDay = {}; // {date_iso: [ScheduleItem]}
  int _currentViewWeekOffset = 0; // 0 for current week, 1 for next, -1 for previous

  // Shift Definitions (Global data)
  ShiftDefinitions? _shiftDefinitions;


  ScheduleProvider(this._authApi);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<StaffMember> get staffForSwaps => _staffForSwaps;
  
  Map<String, dynamic> get consolidatedScheduleData => _consolidatedScheduleData;
  List<SchedulerUser> get usersInCategory => _usersInCategory;
  String get currentConsolidatedViewType => _currentConsolidatedViewType;
  int get currentConsolidatedWeekOffset => _currentConsolidatedWeekOffset;

  // --- NEW: Scheduler Role View Getters ---
  String? get currentSchedulerRole => _currentSchedulerRole;
  int get currentSchedulerWeekOffset => _currentSchedulerWeekOffset;
  Map<String, dynamic>? get currentSchedulerData => _currentSchedulerData;


  // Getters for Availability
  Map<String, dynamic> get availabilityWindowStatus => _availabilityWindowStatus;
  Map<String, List<String>> get myAvailability => _myAvailability;
  List<DateTime> get availabilitySubmissionWeekDates => _availabilitySubmissionWeekDates;
  Map<String, dynamic> get myAssignedScheduleData => _myAssignedScheduleData;

  // Getters for My Schedule
  List<DateTime> get myScheduleWeekDates => _myScheduleWeekDates;
  Map<String, List<ScheduleItem>> get myScheduleByDay => _myScheduleByDay;
  int get currentViewWeekOffset => _currentViewWeekOffset;

  // Getters for Shift Definitions
  ShiftDefinitions? get shiftDefinitions => _shiftDefinitions;

  List<PendingSwap> get pendingSwaps => _pendingSwaps;
  List<SwapHistoryItem> get swapHistory => _swapHistory;
  int get manageSwapsWeekOffset => _manageSwapsWeekOffset;

  List<VolunteeredShiftItem> get actionableVolunteeredShifts => _actionableVolunteeredShifts;
  List<VolunteeredShiftHistoryItem> get volunteeredShiftHistory => _volunteeredShiftHistory;
  int get manageVolunteeredWeekOffset => _manageVolunteeredWeekOffset;

  List<RequiredStaffItem> get requiredStaff => _requiredStaff;
  String get manageRequiredStaffRole => _manageRequiredStaffRole;
  int get manageRequiredStaffWeekOffset => _manageRequiredStaffWeekOffset;

  CategorizedDailyShifts? get dailyShiftsToday => _dailyShiftsToday;

  // --- Fetch Shift Definitions ---
  Future<void> fetchShiftDefinitions() async {
    if (_shiftDefinitions != null) return; // Already loaded
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _shiftDefinitions = await _authApi.getShiftDefinitions();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Availability Window Status ---
  Future<void> fetchAvailabilityWindowStatus() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _availabilityWindowStatus = await _authApi.getAvailabilityWindowStatus();
      
      final String nextWeekStartStr = _availabilityWindowStatus['next_week_start_date'] as String;
      final DateTime nextWeekStartDate = DateTime.parse(nextWeekStartStr).toUtc();
      _availabilitySubmissionWeekDates = [for (int i = 0; i < 7; i++) nextWeekStartDate.add(Duration(days: i))];
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch My Availability ---
  Future<void> fetchMyAvailability() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final Map<String, dynamic> rawAvailability = await _authApi.getMyAvailability(1);
      
      _myAvailability = rawAvailability.map((dateStr, shiftsDynamicList) {
        List<String> shifts;
        if (shiftsDynamicList is List) { // Check if it's a List first
          shifts = shiftsDynamicList.map((e) => e.toString()).toList();
        } else {
          shifts = []; // Default to an empty list if not a List or null
        }
        return MapEntry(dateStr, shifts);
      });

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchMyAvailability: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Submit My Availability ---
  Future<void> submitMyAvailability(List<String> shifts) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitAvailability(shifts);
      _errorMessage = null;
      await fetchMyAvailability(); // Refresh after submission
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch My Assigned Shifts ---
  Future<void> fetchMyAssignedShifts(int weekOffset) async {
  _isLoading = true;
  _errorMessage = null;
  notifyListeners();
  try {
    _currentViewWeekOffset = weekOffset;
    _myAssignedScheduleData = await _authApi.getMyAssignedShifts(weekOffset);
    
    final List<dynamic> weekDatesJson = _myAssignedScheduleData['week_dates'] ?? [];
    _myScheduleWeekDates = weekDatesJson.map((dateStr) => DateTime.parse(dateStr as String)).toList();
    
    _myScheduleByDay = {}; // Clear previous data
    final Map<String, dynamic> scheduleByDayJson = _myAssignedScheduleData['schedule_by_day'] ?? {};
    scheduleByDayJson.forEach((dateIso, shiftsJsonList) {
      _myScheduleByDay[dateIso] = (shiftsJsonList as List<dynamic>)
          .map((shiftJson) => ScheduleItem.fromJson(shiftJson as Map<String, dynamic>))
          .toList();
    });

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR (ScheduleProvider.fetchMyAssignedShifts): $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Helper to get shifts for a specific date from my schedule ---
  List<ScheduleItem> getShiftsForDate(DateTime date) {
    return _myScheduleByDay[date.toIso8601String().substring(0, 10)] ?? [];
  }

  // --- Utility to get formatted shift time display ---
  String getFormattedShiftTimeDisplay(String roleName, String dayName, String shiftType, {String? customStart, String? customEnd}) {
    return _shiftDefinitions?.getShiftTimeDisplayForRole(roleName, dayName, shiftType, customStart: customStart, customEnd: customEnd) ?? '';
  }

  // --- Initial Combined Fetch (e.g., for HomeScreen/init) ---
  Future<void> fetchStaffForSwaps() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _staffForSwaps = await _authApi.getStaffForSwaps();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchStaffForSwaps: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Submit New Swap Request ---
  Future<void> submitNewSwapRequest({
    required int requesterScheduleId,
    required int desiredCoverId,
    String swapPart = 'full',
    int? covererScheduleId, // New parameter
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitNewSwapRequest(
        requesterScheduleId: requesterScheduleId,
        desiredCoverId: desiredCoverId,
        swapPart: swapPart,
        covererScheduleId: covererScheduleId, // Pass it to API
      );
      _errorMessage = null;
      await fetchMyAssignedShifts(_currentViewWeekOffset); // Refresh assigned shifts
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitNewSwapRequest: $_errorMessage');
      rethrow; // Re-throw to handle in UI
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Submit Relinquish Shift Request ---
  Future<void> submitRelinquishShift({
    required int scheduleId,
    String? reason,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitRelinquishShift(
        scheduleId: scheduleId,
        reason: reason,
      );
      _errorMessage = null;
      await fetchMyAssignedShifts(_currentViewWeekOffset); // Refresh assigned shifts
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitRelinquishShift: $_errorMessage');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Initial Combined Fetch (for HomeScreen/init) ---
  @override
  Future<void> fetchInitialScheduleData() async {
    await Future.wait([
      fetchShiftDefinitions(), // Needed globally
      fetchAvailabilityWindowStatus(),
      fetchMyAvailability(),
      fetchMyAssignedShifts(0), // Fetch current week schedule
      fetchStaffForSwaps(),
    ]);
  }

  Future<void> fetchManageSwapsData(int weekOffset) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _manageSwapsWeekOffset = weekOffset;
      final Map<String, dynamic> data = await _authApi.getManageSwapsData(weekOffset);
      _pendingSwaps = (data['pending_swaps'] as List<dynamic>?)
              ?.map((e) => PendingSwap.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      _swapHistory = (data['all_swaps_history'] as List<dynamic>?)
              ?.map((e) => SwapHistoryItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchManageSwapsData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Update Swap Status ---
  Future<void> updateSwapStatus(int swapId, String action, {int? covererId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.updateSwapStatus(swapId, action, covererId: covererId);
      _errorMessage = null;
      await fetchManageSwapsData(_manageSwapsWeekOffset); // Refresh data
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in updateSwapStatus: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Manage Volunteered Shifts Data ---
  Future<void> fetchManageVolunteeredShiftsData(int weekOffset) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _manageVolunteeredWeekOffset = weekOffset;
      final Map<String, dynamic> data = await _authApi.getManageVolunteeredShiftsData(weekOffset);
      _actionableVolunteeredShifts = (data['actionable_volunteered_shifts'] as List<dynamic>?)
              ?.map((e) => VolunteeredShiftItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      _volunteeredShiftHistory = (data['all_volunteered_shifts_history'] as List<dynamic>?)
              ?.map((e) => VolunteeredShiftHistoryItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchManageVolunteeredShiftsData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Update Volunteered Shift Status ---
  Future<void> updateVolunteeredShiftStatus(int vShiftId, String action, {int? approvedVolunteerId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.updateVolunteeredShiftStatus(vShiftId, action, approvedVolunteerId: approvedVolunteerId);
      _errorMessage = null;
      await fetchManageVolunteeredShiftsData(_manageVolunteeredWeekOffset); // Refresh data
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in updateVolunteeredShiftStatus: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Manage Required Staff Data ---
  Future<void> fetchManageRequiredStaffData(String roleName, int weekOffset) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _manageRequiredStaffRole = roleName;
      _manageRequiredStaffWeekOffset = weekOffset;
      final Map<String, dynamic> data = await _authApi.getManageRequiredStaffData(roleName, weekOffset);
      
      final List<dynamic> displayDatesJson = data['display_dates'];
      _requiredStaff = displayDatesJson.map((dateStr) {
        final Map<String, dynamic> reqsJson = data['existing_minimums'][dateStr] ?? {'min_staff': 0, 'max_staff': null};
        return RequiredStaffItem.fromJson(dateStr, reqsJson);
      }).toList();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchManageRequiredStaffData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Update Required Staff ---
  Future<void> updateRequiredStaff(List<RequiredStaffItem> requirements) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final List<Map<String, dynamic>> apiRequirements = requirements.map((req) => {
        'date': req.date.toIso8601String().substring(0, 10),
        'min_staff': req.minStaff,
        'max_staff': req.maxStaff,
      }).toList();

      await _authApi.updateRequiredStaff(
        roleName: _manageRequiredStaffRole,
        weekOffset: _manageRequiredStaffWeekOffset,
        requirements: apiRequirements,
      );
      _errorMessage = null;
      await fetchManageRequiredStaffData(_manageRequiredStaffRole, _manageRequiredStaffWeekOffset); // Refresh data
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in updateRequiredStaff: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Shifts Today Data ---
  Future<void> fetchShiftsTodayData(DateTime targetDate) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dailyShiftsToday = await _authApi.getShiftsTodayData(targetDate);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchShiftsTodayData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchConsolidatedSchedule(String viewType, int weekOffset) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _currentConsolidatedViewType = viewType;
      _currentConsolidatedWeekOffset = weekOffset;
      _consolidatedScheduleData = await _authApi.getConsolidatedSchedule(viewType, weekOffset);
      
      _usersInCategory = (_consolidatedScheduleData['users_in_category'] as List<dynamic>?)
              ?.map((e) => SchedulerUser.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchConsolidatedSchedule: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Helper to get shifts for a specific user and date from consolidated schedule ---
  List<ScheduleItem> getConsolidatedShiftsForUserAndDate(int userId, DateTime date) {
    final dateIso = date.toIso8601String().substring(0, 10);
    final Map<String, dynamic>? userScheduleForWeek = _consolidatedScheduleData['schedule_by_user']?[userId.toString()] as Map<String, dynamic>?;
    final List<dynamic>? shiftsJsonList = userScheduleForWeek?[dateIso];
    
    if (shiftsJsonList == null) return [];
    return shiftsJsonList.map((shiftJson) => ScheduleItem.fromJson(shiftJson as Map<String, dynamic>)).toList();
  }

  // --- NEW: Fetch Role-Specific Scheduler Data ---
  Future<void> fetchSchedulerData(String roleName, int weekOffset) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _currentSchedulerRole = roleName;
      _currentSchedulerWeekOffset = weekOffset;
      _currentSchedulerData = await _authApi.getSchedulerData(roleName, weekOffset);
      
      // Parse users in category for this scheduler role
      _usersInCategory = (_currentSchedulerData!['users'] as List<dynamic>?) // The API endpoint returns 'users'
              ?.map((e) => SchedulerUser.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchSchedulerData: $_errorMessage');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Submit Scheduler Assignments ---
  Future<void> submitSchedulerAssignments(
    String roleName,
    int weekOffset,
    Map<String, List<Map<String, dynamic>>> assignments, // {date_iso: [{user_id, shift_type, start, end}]}
    bool publish,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitSchedulerAssignments(roleName, weekOffset, assignments, publish);
      _errorMessage = null;
      // After submission, re-fetch data to update the view with saved/published state and staffing status
      await fetchSchedulerData(roleName, weekOffset); 
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitSchedulerAssignments: $_errorMessage');
      rethrow; // Allow UI to handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}