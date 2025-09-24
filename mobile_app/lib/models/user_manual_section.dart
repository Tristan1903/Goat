// mobile_app/lib/models/user_manual_section.dart
import '../utils/string_extensions.dart';

class UserManualSection {
  final String title;
  final String content;
  final List<String> roles;

  UserManualSection({
    required this.title,
    required this.content,
    required this.roles,
  });

  factory UserManualSection.fromJson(Map<String, dynamic> json) {
    return UserManualSection(
      title: json['title'] as String,
      content: json['content'] as String,
      roles: List<String>.from(json['roles'] as List<dynamic>),
    );
  }
}