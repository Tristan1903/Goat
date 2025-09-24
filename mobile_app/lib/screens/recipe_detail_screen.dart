import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../widgets/home_button.dart';

class RecipeDetailScreen extends StatelessWidget {
  final Recipe recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recipe.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // --- Ingredients Section ---
            Text(
              'Ingredients:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (recipe.ingredients.isEmpty)
              const Text('No ingredients listed for this recipe.')
            else
              ListView.builder(
                shrinkWrap: true, // Important for nested ListView in SingleChildScrollView
                physics: const NeverScrollableScrollPhysics(), // Disable inner scrolling
                itemCount: recipe.ingredients.length,
                itemBuilder: (context, index) {
                  final ingredient = recipe.ingredients[index];
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                    child: Text(
                      '- ${ingredient.productName}: ${ingredient.quantity.toStringAsFixed(2)} ${ingredient.unitOfMeasure}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                },
              ),
            const SizedBox(height: 20), // Spacing after ingredients

            // --- Instructions ---
            Text(
              'Instructions:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              recipe.instructions,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}