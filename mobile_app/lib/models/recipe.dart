import 'recipe_ingredient.dart';

class Recipe {
  final int id;
  final String name;
  final String instructions;
  final List<RecipeIngredient> ingredients; // <--- NEW: List of ingredients

  Recipe({
    required this.id,
    required this.name,
    required this.instructions,
    required this.ingredients, // <--- NEW: Include in constructor
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    // Map the list of ingredient JSON maps to RecipeIngredient objects
    final List<dynamic> ingredientsJson = json['ingredients'] ?? [];
    final List<RecipeIngredient> parsedIngredients = ingredientsJson
        .map((ingredientJson) => RecipeIngredient.fromJson(ingredientJson as Map<String, dynamic>))
        .toList();

    return Recipe(
      id: json['id'] as int,
      name: json['name'] as String,
      instructions: json['instructions'] as String,
      ingredients: parsedIngredients, // <--- NEW: Assign parsed ingredients
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'instructions': instructions,
      'ingredients': ingredients.map((ri) => ri.toJson()).toList(), // <--- NEW
    };
  }
}