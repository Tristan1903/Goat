// mobile_app/lib/models/role_item.dart
import '../utils/string_extensions.dart';

class RoleItem {
  final int id;
  final String name;

  RoleItem({
    required this.id,
    required this.name,
  });

  factory RoleItem.fromJson(Map<String, dynamic> json) {
    return RoleItem(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  String get formattedName => name.toTitleCase();
}