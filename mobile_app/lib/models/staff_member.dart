// mobile_app/lib/models/staff_member.dart
// ...

class StaffMember {
  final int id;
  final String fullName;
  final String username; // <--- NEW: Add username field
  final List<String>? roles;

  StaffMember({
    required this.id,
    required this.fullName,
    required this.username, // <--- NEW: Include in constructor
    this.roles,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      username: json['username'] as String, // <--- NEW: Parse username
      roles: (json['roles'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );
  }
}