// mobile_app/lib/models/announcement_item.dart
import 'package:intl/intl.dart';
import 'package:flutter/material.dart'; // For Color
import '../utils/string_extensions.dart'; // For toTitleCase()

class AnnouncementItem {
  final int id;
  final int userId;
  final String userFullName;
  final String title;
  final String message;
  final String category;
  final DateTime timestamp;
  final String? actionLink; // <--- NEW
  final List<String> targetRoles; // <--- NEW

  AnnouncementItem({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    this.actionLink, // <--- NEW
    required this.targetRoles, // <--- NEW
  });

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) {
    return AnnouncementItem(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      userFullName: json['user_full_name'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      category: json['category'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      actionLink: json['action_link'] as String?, // <--- NEW
      targetRoles: List<String>.from(json['target_roles'] as List<dynamic>? ?? []), // <--- NEW, handle null
    );
  }

  String get formattedTimestamp => DateFormat('MMM d, yyyy HH:mm').format(timestamp);

  Color get categoryColor {
    switch (category) {
      case 'Urgent': return Colors.red;
      case 'Late Arrival': return Colors.orange;
      default: return Colors.blueGrey;
    }
  }
}