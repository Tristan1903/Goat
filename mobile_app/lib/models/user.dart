// mobile_app/lib/models/user.dart
import 'package:intl/intl.dart'; // For DateFormat

class User {
  final int id;
  final String username;
  final String fullName;
  final String? email; // Can be null
  final List<String> roles; // List of role names
  final bool isSuspended;
  final DateTime? suspensionEndDate;
  final String? suspensionDocumentPath;
  final bool passwordResetRequested;
  final DateTime? lastSeen;
  final bool forceLogoutRequested;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    required this.roles,
    this.isSuspended = false,
    this.suspensionEndDate,
    this.suspensionDocumentPath,
    this.passwordResetRequested = false,
    this.lastSeen,
    this.forceLogoutRequested = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      roles: List<String>.from(json['roles'] as List<dynamic>),
      isSuspended: json['is_suspended'] as bool? ?? false, // Default to false if not provided
      suspensionEndDate: json['suspension_end_date'] != null
          ? DateTime.parse(json['suspension_end_date'] as String)
          : null,
      suspensionDocumentPath: json['suspension_document_path'] as String?,
      passwordResetRequested: json['password_reset_requested'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      forceLogoutRequested: json['force_logout_requested'] as bool? ?? false,
    );
  }

  String get formattedSuspensionEndDate => suspensionEndDate != null ? DateFormat('MMM d, yyyy').format(suspensionEndDate!) : 'N/A';
  String get formattedLastSeen => lastSeen != null ? DateFormat('MMM d, yyyyy HH:mm').format(lastSeen!) : 'N/A';

  // Helper for role display (already implemented)
  bool hasRole(String roleName) => roles.contains(roleName);
}