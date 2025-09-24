// mobile_app/lib/models/announcement.dart
import 'package:flutter/material.dart'; // Just for Color, can remove if not using it
import 'package:intl/intl.dart'; // For date formatting in UI

class Announcement {
  final int id;
  final String title;
  final String message;
  final String category;
  final DateTime timestamp;
  final String postedBy;
  final String? actionLink; // Nullable link for actionable announcements

  Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    required this.postedBy,
    this.actionLink,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as int,
      title: json['title'] as String,
      message: json['message'] as String,
      category: json['category'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String), // Parse ISO string to DateTime
      postedBy: json['posted_by'] as String,
      actionLink: json['action_link'] as String?,
    );
  }

  // Helper for displaying time
  String get formattedTimestamp {
    return DateFormat('MMM d, hh:mm a').format(timestamp.toLocal());
  }

  // Helper for category badge color (optional, for UI)
  Color get categoryColor {
    switch (category) {
      case 'Urgent':
        return Colors.red;
      case 'Late Arrival':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }
}