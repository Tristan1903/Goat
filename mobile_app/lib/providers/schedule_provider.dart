// mobile_app/lib/providers/schedule_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/schedule.dart'; // ScheduleItem and ShiftDefinitions
import '../models/staff_member.dart';
import '../models/shift_management.dart'; // <--- NEW IMPORT



class ScheduleProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;
  List<StaffMember> _staffForSwaps = [];

  // Availability Submission State
  Map<String, dynamic> _availabilityWindowStatus = {}; // {is_open, start_time_utc, end_time_utc}
  Map<String, List<String>> _myAvailability = {};
  List<DateTime> _availabilitySubmissionWeekDates = [];

  Map<String, dynamic> _consolidatedScheduleData = {}; // Raw data
  List<SchedulerUser> _usersInCategory = []; // Users for the current consolidated view
  String _currentConsolidatedViewType = 'boh'; // Default view type (boh, foh, managers)
  int _currentConsolidatedWeekOffset = 0;


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

  // Getters for Availability
  Map<String, dynamic> get availabilityWindowStatus => _availabilityWindowStatus;
  Map<String, List<String>> get myAvailability => _myAvailability;
  List<DateTime> get availabilitySubmissionWeekDates => _availabilitySubmissionWeekDates; // <--- NEW getter
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
      
      // --- NEW: Calculate next week's dates based on API response ---
      final String nextWeekStartStr = _availabilityWindowStatus['next_week_start_date'] as String;
      final DateTime nextWeekStartDate = DateTime.parse(nextWeekStartStr).toUtc();
      _availabilitySubmissionWeekDates = [for (int i = 0; i < 7; i++) nextWeekStartDate.add(Duration(days: i))];
      // --- END NEW ---
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
        // --- MODIFIED: More robust handling of shiftsDynamicList ---
        List<String> shifts;
        if (shiftsDynamicList is List) { // Check if it's a List first
          shifts = shiftsDynamicList.map((e) => e.toString()).toList();
        } else {
          shifts = []; // Default to an empty list if not a List or null
        }
        return MapEntry(dateStr, shifts);
        // --- END MODIFIED ---
      });

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchMyAvailability: $_errorMessage'); // Add specific debug for this
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
    
    print('DEBUG (ScheduleProvider): Raw _myAssignedScheduleData from API: $_myAssignedScheduleData'); // <--- ADD THIS
    
    // Parse week dates (List<String> to List<DateTime>)
    final List<dynamic> weekDatesJson = _myAssignedScheduleData['week_dates'] ?? [];
    _myScheduleWeekDates = weekDatesJson.map((dateStr) => DateTime.parse(dateStr as String)).toList();
    
    print('DEBUG (ScheduleProvider): Parsed _myScheduleWeekDates (Mon-Sun): $_myScheduleWeekDates');

      // Parse schedule by day (Map<String, List<Map<String, dynamic>>> to Map<String, List<ScheduleItem>>)
      _myScheduleByDay = {}; // Clear previous data
      final Map<String, dynamic> scheduleByDayJson = _myAssignedScheduleData['schedule_by_day'] ?? {};
      scheduleByDayJson.forEach((dateIso, shiftsJsonList) {
        _myScheduleByDay[dateIso] = (shiftsJsonList as List<dynamic>)
            .map((shiftJson) => ScheduleItem.fromJson(shiftJson as Map<String, dynamic>))
            .toList();
      });
      // --- END NEW ---

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR (ScheduleProvider.fetchMyAssignedShifts): $_errorMessage'); // <--- ADD THIS
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

  // --- NEW: Submit New Swap Request ---
  Future<void> submitNewSwapRequest({
    required int requesterScheduleId,
    required int desiredCoverId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitNewSwapRequest(
        requesterScheduleId: requesterScheduleId,
        desiredCoverId: desiredCoverId,
      );
      _errorMessage = null;
      await fetchMyAssignedShifts(_currentViewWeekOffset); // Refresh assigned shifts
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitNewSwapRequest: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Submit Relinquish Shift Request ---
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
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Initial Combined Fetch (for HomeScreen/init) ---
  // MODIFIED: Also fetch staff for swaps globally
  @override
  Future<void> fetchInitialScheduleData() async {
    await Future.wait([
      fetchShiftDefinitions(), // Needed globally for all schedule screens
      fetchAvailabilityWindowStatus(),
      fetchMyAvailability(),
      fetchMyAssignedShifts(0), // Fetch current week schedule
      fetchStaffForSwaps(),
      // Add initial fetches for manager views if they are always loaded on dashboard
      // For now, load these on their respective screens
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

  // --- NEW: Update Swap Status ---
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

  // --- NEW: Fetch Manage Volunteered Shifts Data ---
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

  // --- NEW: Update Volunteered Shift Status ---
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

  // --- NEW: Fetch Manage Required Staff Data ---
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

  // --- NEW: Update Required Staff ---
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

  // --- NEW: Fetch Shifts Today Data ---
  Future<void> fetchShiftsTodayData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dailyShiftsToday = await _authApi.getShiftsTodayData();
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
      
      // Parse users in category
      _usersInCategory = (_consolidatedScheduleData['users_in_category'] as List<dynamic>?)
              ?.map((e) => SchedulerUser.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];

      // The `schedule_by_user` part of _consolidatedScheduleData will be accessed directly by the UI.

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
    final Map<String, dynamic>? userScheduleForWeek = _consolidatedScheduleData['schedule_by_user']?[userId.toString()] as Map<String, dynamic>?; // User ID is string key
    final List<dynamic>? shiftsJsonList = userScheduleForWeek?[dateIso];
    
    if (shiftsJsonList == null) return [];
    return shiftsJsonList.map((shiftJson) => ScheduleItem.fromJson(shiftJson as Map<String, dynamic>)).toList();
  }
}