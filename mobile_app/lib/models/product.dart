class Product {
  final int id;
  final String name;
  final String type;
  final String unitOfMeasure;
  double? unitPrice;
  final String? productNumber;

  // For inventory counting, we'll add these properties
  double? currentBodAmount; // Beginning of Day amount for the product (always today's BOD)
  double? currentCountAmount; // Amount last counted by the user (actual input value for the current day)
  String? countComment; // Comment for the count
  String? lastCountType; // <--- NEW: e.g., 'First Count', 'Corrections Count'

  Product({
    required this.id,
    required this.name,
    required this.type,
    required this.unitOfMeasure,
    this.unitPrice,
    this.productNumber,
    this.currentBodAmount,
    this.currentCountAmount,
    this.countComment,
    this.lastCountType, // <--- NEW
  });

  
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      unitOfMeasure: json['unit_of_measure'] as String,
      unitPrice: (json['unit_price'] as num?)?.toDouble(), // Handle null and num to double
      productNumber: json['product_number'] as String?,

      currentBodAmount: null,
      currentCountAmount: null,
      countComment: null,
    );
  }

  factory Product.fromBodJson(Map<String, dynamic> json) {
    return Product(
      id: json['product_id'] as int,
      name: json['product_name'] as String,
      unitOfMeasure: json['unit_of_measure'] as String,
      type: 'N/A', // BOD data might not have type, set default
      currentBodAmount: (json['bod_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'unit_of_measure': unitOfMeasure,
      'unit_price': unitPrice,
      'product_number': productNumber,
      'currentBodAmount': currentBodAmount,
      'currentCountAmount': currentCountAmount,
      'countComment': countComment,
    };
  }
}