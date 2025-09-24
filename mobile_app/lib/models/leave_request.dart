// mobile_app/lib/models/leave_request.dart
import 'package:intl/intl.dart';

class LeaveRequest {
  final int id;
  final int userId;
  final String userFullName; // Name of the user who made the request
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String? documentPath; // URL to the supporting document
  final String status; // 'Pending', 'Approved', 'Denied'
  final DateTime timestamp;

  LeaveRequest({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.documentPath,
    required this.status,
    required this.timestamp,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    return LeaveRequest(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      userFullName: json['user_full_name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      reason: json['reason'] as String,
      documentPath: json['document_path'] as String?,
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  String get formattedDateRange {
    return '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}';
  }

  String get formattedSubmittedDate {
    return DateFormat('MMM d, yyyy HH:mm').format(timestamp);
  }
}