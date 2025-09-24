// mobile_app/lib/models/booking_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BookingItem {
  final int id;
  final String customerName;
  final String? contactInfo;
  final int partySize;
  final DateTime bookingDate;
  final String bookingTime; // Stored as HH:MM string
  final String? notes;
  final String status; // 'Pending', 'Confirmed', 'Cancelled', 'Completed'
  final DateTime timestamp; // When booking was created in DB
  final int userId; // ID of the user who logged it
  final String userFullName; // Name of the user who logged it

  BookingItem({
    required this.id,
    required this.customerName,
    this.contactInfo,
    required this.partySize,
    required this.bookingDate,
    required this.bookingTime,
    this.notes,
    required this.status,
    required this.timestamp,
    required this.userId,
    required this.userFullName,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    return BookingItem(
      id: json['id'] as int,
      customerName: json['customer_name'] as String,
      contactInfo: json['contact_info'] as String?,
      partySize: json['party_size'] as int,
      bookingDate: DateTime.parse(json['booking_date'] as String),
      bookingTime: json['booking_time'] as String,
      notes: json['notes'] as String?,
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      userId: json['user_id'] as int,
      userFullName: json['user_full_name'] as String,
    );
  }

  String get formattedBookingDate => DateFormat('MMM d, yyyy').format(bookingDate);
  String get formattedBookingTime => DateFormat('hh:mm a').format(DateFormat('HH:mm').parse(bookingTime));
  String get formattedDateTime => '$formattedBookingDate at $formattedBookingTime';

  Color get statusColor {
    switch (status) {
      case 'Confirmed': return Colors.green;
      case 'Pending': return Colors.orange;
      case 'Cancelled': return Colors.red;
      case 'Completed': return Colors.blueGrey;
      default: return Colors.grey;
    }
  }
}