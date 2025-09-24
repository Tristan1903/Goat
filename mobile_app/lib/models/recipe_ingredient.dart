class RecipeIngredient {
  final int productId;
  final String productName;
  final String unitOfMeasure;
  final double quantity;

  RecipeIngredient({
    required this.productId,
    required this.productName,
    required this.unitOfMeasure,
    required this.quantity,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      unitOfMeasure: json['unit_of_measure'] as String,
      quantity: (json['quantity'] as num).toDouble(), // num to handle both int/double from JSON
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'unit_of_measure': unitOfMeasure,
      'quantity': quantity,
    };
  }
}