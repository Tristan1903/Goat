class Location {
  final int id;
  final String name;
  final String slug;
  final String? status;

  Location({
    required this.id,
    required this.name,
    required this.slug,
    this.status,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'],
      name: json['name'] as String,
      slug: json['slug'] as String,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'status': status,
    };
  }
}