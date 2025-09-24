// mobile_app/lib/models/warning_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WarningItem {
  final int id;
  final int userId;
  final String userFullName;
  final int issuedById;
  final String issuedByFullName;
  final DateTime dateIssued;
  final String reason;
  final String severity; // 'Minor', 'Major', 'Critical'
  final String status; // 'Active', 'Resolved', 'Expired'
  final String? notes;
  final DateTime? resolutionDate;
  final int? resolvedById;
  final String? resolvedByFullName;
  final DateTime timestamp; // When the warning was created in DB

  WarningItem({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.issuedById,
    required this.issuedByFullName,
    required this.dateIssued,
    required this.reason,
    required this.severity,
    required this.status,
    this.notes,
    this.resolutionDate,
    this.resolvedById,
    this.resolvedByFullName,
    required this.timestamp,
  });

  factory WarningItem.fromJson(Map<String, dynamic> json) {
    return WarningItem(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      userFullName: json['user_full_name'] as String,
      issuedById: json['issued_by_id'] as int,
      issuedByFullName: json['issued_by_full_name'] as String,
      dateIssued: DateTime.parse(json['date_issued'] as String),
      reason: json['reason'] as String,
      severity: json['severity'] as String,
      status: json['status'] as String,
      notes: json['notes'] as String?,
      resolutionDate: json['resolution_date'] != null ? DateTime.parse(json['resolution_date'] as String) : null,
      resolvedById: json['resolved_by_id'] as int?,
      resolvedByFullName: json['resolved_by_full_name'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  String get formattedDateIssued => DateFormat('MMM d, yyyy').format(dateIssued);
  String get formattedTimestamp => DateFormat('MMM d, yyyy HH:mm').format(timestamp);
  String get formattedResolutionDate => resolutionDate != null ? DateFormat('MMM d, yyyy').format(resolutionDate!) : 'N/A';

  Color get severityColor {
    switch (severity) {
      case 'Critical': return Colors.red;
      case 'Major': return Colors.orange;
      case 'Minor': return Colors.blue;
      default: return Colors.grey;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'Active': return Colors.blueGrey;
      case 'Resolved': return Colors.green;
      case 'Expired': return Colors.grey;
      default: return Colors.grey;
    }
  }
}