// mobile_app/lib/models/schedule.dart
import 'package:intl/intl.dart';

// Model for a single submitted availability or assigned shift
class ScheduleItem {
  final int? id; // Null for availability submission, present for assigned shifts
  final int userId; // <--- THIS IS A NON-NULLABLE INT
  final String? userFullName;
  final DateTime shiftDate;
  final String shiftType;
  final String? startTimeStr;
  final String? endTimeStr;
  final String? status;
  final String? requesterFullName;
  final String? relinquishReason;
  final bool? isOnLeave;

  ScheduleItem({
    this.id,
    required this.userId, // <--- Required means it must be provided
    this.userFullName,
    required this.shiftDate,
    required this.shiftType,
    this.startTimeStr,
    this.endTimeStr,
    this.status,
    this.requesterFullName,
    this.relinquishReason,
    this.isOnLeave,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final dynamic rawUserId = json['user_id'];
    int parsedUserId;
    if (rawUserId is int) {
      parsedUserId = rawUserId;
    } else if (rawUserId is String) {
      parsedUserId = int.tryParse(rawUserId) ?? 0; // Try parse, fallback to 0
    } else {
      parsedUserId = 0; // Default to 0 if unexpected type
    }

    return ScheduleItem(
      id: json['id'] as int?,
      userId: parsedUserId, // Use the safely parsed ID
      userFullName: json['user_full_name'] as String?,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      shiftType: json['assigned_shift'] as String,
      startTimeStr: json['start_time_str'] as String?,
      endTimeStr: json['end_time_str'] as String?,
      status: json['swap_request_status'] as String? ?? json['volunteered_cycle_status'] as String?,
      requesterFullName: json['requester_full_name'] as String?,
      relinquishReason: json['relinquish_reason'] as String?,
      isOnLeave: json['is_on_leave'] as bool?,
    );
  }

  // Factory for availability data, which is simpler
  factory ScheduleItem.fromAvailabilityJson(String dateStr, String type) {
    return ScheduleItem(
      userId: 0, // Not relevant for this simple availability item
      shiftDate: DateTime.parse(dateStr),
      shiftType: type,
    );
  }

  String get formattedDate {
    return DateFormat('EEE, MMM d').format(shiftDate); // e.g., Tue, Oct 20
  }

  // Helper to format the time display based on shift type and custom times
  String get formattedTimeDisplay {
    if (startTimeStr != null && endTimeStr != null) {
      if (endTimeStr?.toLowerCase() == 'close') {
        return '($startTimeStr - Close)';
      }
      return '($startTimeStr - $endTimeStr)';
    }
    // Fallback to general descriptions if no custom times are set or available
    switch (shiftType) {
      case 'Day': return '(Day Shift)';
      case 'Night': return '(Night Shift)';
      case 'Double': return '(Full Day)';
      case 'Open': return '(Flexible Slot)';
      case 'Split Double': return '(Split Shift)';
      case 'Double A': return '(Double Shift)';
      case 'Double B': return '(Double Shift)';
      default: return '';
    }
  }
}

// Model for Shift Definitions
class ShiftDefinitions {
  final Map<String, dynamic> roleShiftDefinitions; // Maps role -> day -> shift -> times
  final List<String> schedulerShiftTypesGeneric; // Generic list of types

  ShiftDefinitions({
    required this.roleShiftDefinitions,
    required this.schedulerShiftTypesGeneric,
  });

  factory ShiftDefinitions.fromJson(Map<String, dynamic> json) {
    return ShiftDefinitions(
      roleShiftDefinitions: json['role_shift_definitions'] as Map<String, dynamic>,
      schedulerShiftTypesGeneric: List<String>.from(json['scheduler_shift_types_generic'] as List<dynamic>),
    );
  }

  String getShiftTimeDisplayForRole(String roleName, String dayName, String shiftType, {String? customStart, String? customEnd}) {
    // If custom times are provided (from an assigned shift), use them
    if (customStart != null && customEnd != null) {
      final endDisplay = customEnd.toLowerCase() == 'close' ? 'Close' : customEnd;
      return '($customStart - $endDisplay)';
    }

    // Fallback to predefined role/day specific times
    final roleDef = roleShiftDefinitions[roleName] ?? roleShiftDefinitions['manager']; // Fallback to manager
    if (roleDef == null) return '';

    final dayDef = roleDef[dayName] ?? roleDef['default'];
    if (dayDef == null) return '';

    final times = dayDef[shiftType];
    if (times != null && times['start'] != null && times['end'] != null) {
      if (times['start'] == 'Specified by Scheduler' || times['end'] == 'Specified by Scheduler') {
        return '(Custom Times)'; // Indicate it needs custom input
      }
      return '(${times['start']} - ${times['end']})';
    }
    return '';
  }

  List<String> getRoleSpecificShiftTypes(String roleName, String dayName) {
    final Map<String, dynamic>? roleDef = roleShiftDefinitions[roleName] as Map<String, dynamic>?;
    
    Map<String, dynamic>? effectiveRoleDef = roleDef;
    // Fallback for roles without explicit definitions, e.g., 'system_admin' to 'manager'
    if (effectiveRoleDef == null) {
      effectiveRoleDef = roleShiftDefinitions['manager'] as Map<String, dynamic>?;
    }
    if (effectiveRoleDef == null) {
      return schedulerShiftTypesGeneric; // Fallback to generic if even manager default is missing
    }

    final Map<String, dynamic>? dayDef = effectiveRoleDef[dayName] as Map<String, dynamic>?;
    Map<String, dynamic>? effectiveDayDef = dayDef;

    if (effectiveDayDef == null && effectiveRoleDef.containsKey('default')) {
      effectiveDayDef = effectiveRoleDef['default'] as Map<String, dynamic>?;
    }
    if (effectiveDayDef == null) {
      return []; // No specific definition found
    }

    return List<String>.from(effectiveDayDef.keys); // Return list of shift types (keys) for that day/role
  }
}