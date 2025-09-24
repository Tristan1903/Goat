// mobile_app/lib/screens/recipe_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recipe.dart';
import '../providers/inventory_provider.dart';
import 'recipe_detail_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  String _searchQuery = ''; // For searching recipes

  @override
  void initState() {
    super.initState();
    // Fetch all recipes when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InventoryProvider>(context, listen: false).fetchAllRecipes();
    });
  }

  // Filter recipes based on search query
  List<Recipe> _getFilteredRecipes(List<Recipe> allRecipes) {
    if (_searchQuery.isEmpty) {
      return allRecipes;
    } else {
      return allRecipes
          .where((recipe) => recipe.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe Book'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, inventoryProvider, child) {
          if (inventoryProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (inventoryProvider.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${inventoryProvider.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (inventoryProvider.allRecipes.isEmpty) {
            return const Center(
              child: Text(
                'No recipes found. Please add recipes in the web portal.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredRecipes = _getFilteredRecipes(inventoryProvider.allRecipes);

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Search Recipes',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredRecipes.length,
                  itemBuilder: (context, index) {
                    final recipe = filteredRecipes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long, color: Colors.green),
                        title: Text(recipe.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          // Navigate to RecipeDetailScreen
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) => RecipeDetailScreen(recipe: recipe),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}