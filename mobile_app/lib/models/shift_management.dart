// mobile_app/lib/models/shift_management.dart
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'; // For Color
import './staff_member.dart';

// Re-using StaffMember from models/staff_member.dart

// ----------------------------------------------------
// Models for Manage Swaps Screen
// ----------------------------------------------------
class PendingSwap {
  final int id;
  final int scheduleId;
  final int requesterId;
  final String requesterFullName;
  final int? covererId; // Suggested coverer
  final String? covererFullName; // Suggested coverer's name
  final String assignedShift; // The shift being swapped
  final DateTime shiftDate;
  final String status; // Should be 'Pending' for this list
  final DateTime timestamp;
  final String swapPart;
  final List<StaffMember> eligibleCovers; // Staff eligible to cover this specific swap+

  PendingSwap({
    required this.id,
    required this.scheduleId,
    required this.requesterId,
    required this.requesterFullName,
    this.covererId,
    this.covererFullName,
    required this.assignedShift,
    required this.shiftDate,
    required this.status,
    required this.timestamp,
    required this.swapPart,
    required this.eligibleCovers,
  });

  factory PendingSwap.fromJson(Map<String, dynamic> json) {
    return PendingSwap(
      id: json['id'] as int,
      scheduleId: json['schedule_id'] as int,
      requesterId: json['requester_id'] as int,
      requesterFullName: json['requester_full_name'] as String,
      covererId: json['coverer_id'] as int?,
      covererFullName: json['coverer_full_name'] as String?,
      assignedShift: json['assigned_shift'] as String,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      swapPart: json['swap_part'] as String,
      eligibleCovers: (json['eligible_covers'] as List<dynamic>?)
              ?.map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get formattedShiftDate => DateFormat('EEE, MMM d').format(shiftDate);
  String get formattedTimestamp => DateFormat('MMM d, HH:mm').format(timestamp);
}

class SwapHistoryItem {
  final int id;
  final int scheduleId;
  final DateTime shiftDate;
  final String assignedShift;
  final String requesterFullName;
  final String? covererFullName;
  final String status;
  final DateTime timestamp;
  final String swapPart;

  SwapHistoryItem({
    required this.id,
    required this.scheduleId,
    required this.shiftDate,
    required this.assignedShift,
    required this.requesterFullName,
    this.covererFullName,
    required this.status,
    required this.timestamp,
    required this.swapPart,
  });

  factory SwapHistoryItem.fromJson(Map<String, dynamic> json) {
    return SwapHistoryItem(
      id: json['id'] as int,
      scheduleId: json['schedule_id'] as int,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      assignedShift: json['assigned_shift'] as String,
      requesterFullName: json['requester_full_name'] as String,
      covererFullName: json['coverer_full_name'] as String?,
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      swapPart: json['swap_part'] as String,
    );
  }

  String get formattedShiftDate => DateFormat('MMM d').format(shiftDate);
  String get formattedTimestamp => DateFormat('MMM d, HH:mm').format(timestamp);

  Color get statusColor {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Denied':
        return Colors.red;
      default: // Pending, etc.
        return Colors.orange;
    }
  }
}

// ----------------------------------------------------
// Models for Manage Volunteered Shifts Screen
// ----------------------------------------------------
class VolunteeredShiftItem {
  final int id;
  final int scheduleId;
  final int requesterId;
  final String requesterFullName;
  final String assignedShift;
  final DateTime shiftDate;
  final String? relinquishReason;
  final String status; // 'Open', 'PendingApproval' for actionable
  final List<StaffMember> volunteers; // All who volunteered
  final List<StaffMember> eligibleVolunteersForDropdown; // Eligible for manager to pick

  VolunteeredShiftItem({
    required this.id,
    required this.scheduleId,
    required this.requesterId,
    required this.requesterFullName,
    required this.assignedShift,
    required this.shiftDate,
    this.relinquishReason,
    required this.status,
    required this.volunteers,
    required this.eligibleVolunteersForDropdown,
  });

  factory VolunteeredShiftItem.fromJson(Map<String, dynamic> json) {
    return VolunteeredShiftItem(
      id: json['id'] as int,
      scheduleId: json['schedule_id'] as int,
      requesterId: json['requester_id'] as int,
      requesterFullName: json['requester_full_name'] as String,
      assignedShift: json['assigned_shift'] as String,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      relinquishReason: json['relinquish_reason'] as String?,
      status: json['status'] as String,
      volunteers: (json['volunteers'] as List<dynamic>?)
              ?.map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      eligibleVolunteersForDropdown: (json['eligible_volunteers_for_dropdown'] as List<dynamic>?)
              ?.map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get formattedShiftDate => DateFormat('EEE, MMM d').format(shiftDate);
}

class VolunteeredShiftHistoryItem {
  final int id;
  final int scheduleId;
  final DateTime shiftDate;
  final String assignedShift;
  final String requesterFullName;
  final String? approvedVolunteerFullName;
  final String status;
  final DateTime timestamp;
  final List<String> volunteersOffered; // List of names

  VolunteeredShiftHistoryItem({
    required this.id,
    required this.scheduleId,
    required this.shiftDate,
    required this.assignedShift,
    required this.requesterFullName,
    this.approvedVolunteerFullName,
    required this.status,
    required this.timestamp,
    required this.volunteersOffered,
  });

  factory VolunteeredShiftHistoryItem.fromJson(Map<String, dynamic> json) {
    return VolunteeredShiftHistoryItem(
      id: json['id'] as int,
      scheduleId: json['schedule_id'] as int,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      assignedShift: json['assigned_shift'] as String,
      requesterFullName: json['requester_full_name'] as String,
      approvedVolunteerFullName: json['approved_volunteer_full_name'] as String?,
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      volunteersOffered: (json['volunteers_offered'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  String get formattedShiftDate => DateFormat('MMM d').format(shiftDate);
  String get formattedTimestamp => DateFormat('MMM d, HH:mm').format(timestamp);

  Color get statusColor {
    switch (status) {
      case 'Approved':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      case 'Open':
        return Colors.blue;
      default: // PendingApproval, etc.
        return Colors.orange;
    }
  }
}

// ----------------------------------------------------
// Models for Manage Staff Minimums Screen
// ----------------------------------------------------
class RequiredStaffItem {
  final DateTime date;
  int minStaff; // Mutable, as user will edit
  int? maxStaff; // Mutable, as user will edit

  RequiredStaffItem({
    required this.date,
    required this.minStaff,
    this.maxStaff,
  });

  factory RequiredStaffItem.fromJson(String dateStr, Map<String, dynamic> json) {
    return RequiredStaffItem(
      date: DateTime.parse(dateStr),
      minStaff: json['min_staff'] as int,
      maxStaff: json['max_staff'] as int?,
    );
  }

  String get formattedDate => DateFormat('EEE, MMM d').format(date);
}

// ----------------------------------------------------
// Models for Daily Shifts Screen
// ----------------------------------------------------
class DailyShiftEntry {
  final int userId;
  final String userName;
  final List<String> roles; // Formatted roles
  final String assignedShift;
  final String timeDisplay; // Already formatted string

  DailyShiftEntry({
    required this.userId,
    required this.userName,
    required this.roles,
    required this.assignedShift,
    required this.timeDisplay,
  });

  factory DailyShiftEntry.fromJson(Map<String, dynamic> json) {
    return DailyShiftEntry(
      userId: json['user_id'] as int,
      userName: json['user_name'] as String,
      roles: (json['roles'] as List<dynamic>).map((e) => e.toString()).toList() ?? [],
      assignedShift: json['assigned_shift'] as String,
      timeDisplay: json['time_display'] as String,
    );
  }
}

class CategorizedDailyShifts {
  final DateTime todayDate;
  final Map<String, List<DailyShiftEntry>> shiftsByRoleCategorized; // e.g., {'Managers': [shift1, shift2]}
  final List<String> sortedRoleCategories; // To maintain order of display

  CategorizedDailyShifts({
    required this.todayDate,
    required this.shiftsByRoleCategorized,
    required this.sortedRoleCategories,
  });

  factory CategorizedDailyShifts.fromJson(Map<String, dynamic> json) {
    final Map<String, List<DailyShiftEntry>> parsedShifts = {};
    (json['shifts_by_role_categorized'] as Map<String, dynamic>).forEach((category, shiftsList) {
      parsedShifts[category] = (shiftsList as List<dynamic>?)
              ?.map((e) => DailyShiftEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    });

    return CategorizedDailyShifts(
      todayDate: DateTime.parse(json['today_date'] as String),
      shiftsByRoleCategorized: parsedShifts,
      sortedRoleCategories: (json['sorted_role_categories'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    );
  }  
}

class SchedulerUser {
  final int id;
  final String fullName;
  final List<String> roles;

  SchedulerUser({required this.id, required this.fullName, required this.roles});

  factory SchedulerUser.fromJson(Map<String, dynamic> json) {
    return SchedulerUser(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      roles: List<String>.from(json['roles'] as List<dynamic>),
    );
  }
}

// Represents staffing status for a specific day
class StaffingStatus {
  final DateTime date;
  final int minStaff;
  final int? maxStaff;
  final int assignedCount;
  final String statusClass; // 'success', 'warning', 'danger', 'muted'
  final String statusText; // 'Good', 'Overstaffed', 'Understaffed', 'No Req.'

  StaffingStatus({
    required this.date,
    required this.minStaff,
    this.maxStaff,
    required this.assignedCount,
    required this.statusClass,
    required this.statusText,
  });

  factory StaffingStatus.fromJson(String dateStr, Map<String, dynamic> json) {
    return StaffingStatus(
      date: DateTime.parse(dateStr),
      minStaff: json['min_staff'] as int,
      maxStaff: json['max_staff'] as int?,
      assignedCount: json['assigned_count'] as int,
      statusClass: json['status_class'] as String,
      statusText: json['status_text'] as String,
    );
  }

  Color get statusColor {
    switch (statusClass) {
      case 'success': return Colors.green;
      case 'warning': return Colors.orange;
      case 'danger': return Colors.red;
      default: return Colors.blueGrey;
    }
  }
}