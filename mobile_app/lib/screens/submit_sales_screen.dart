import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/recipe.dart';
import '../providers/inventory_provider.dart';
import 'package:intl/intl.dart'; // For date formatting
import '../widgets/home_button.dart';

class SubmitSalesScreen extends StatefulWidget {
  const SubmitSalesScreen({super.key});

  @override
  State<SubmitSalesScreen> createState() => _SubmitSalesScreenState();
}

class _SubmitSalesScreenState extends State<SubmitSalesScreen> {
  DateTime _selectedDate = DateTime.now(); // Default to today
  final List<Map<String, dynamic>> _manualSalesEntries = [];
  final List<Map<String, dynamic>> _cocktailSalesEntries = [];

  // Controllers for dynamically added fields
  final Map<int, TextEditingController> _manualProductQtyControllers = {};
  final Map<int, TextEditingController> _cocktailQtyControllers = {};

  // Products and recipes available for dropdowns
  List<Product> _availableProducts = [];
  List<Recipe> _availableRecipes = [];

  // Track selected IDs to prevent duplicates in dropdowns
  final Set<int> _selectedManualProductIds = {};
  final Set<int> _selectedCocktailRecipeIds = {};

  @override
  void initState() {
    super.initState();
    _fetchProductsAndRecipes();
    _addManualSalesEntry(); // Add initial blank entry
    _addCocktailSalesEntry(); // Add initial blank entry
  }

  Future<void> _fetchProductsAndRecipes() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    await Future.wait([
      inventoryProvider.fetchAllProducts(), // Populates inventoryProvider.allProducts (List<Product>)
      inventoryProvider.fetchAllRecipes(),  // Populates inventoryProvider.allRecipes (List<Recipe>)
    ]);
    setState(() {
      _availableProducts = inventoryProvider.allProducts; // <--- Correct assignment
      _availableRecipes = inventoryProvider.allRecipes;   // <--- Correct assignment
    });
  }

  // --- Date Picker ---
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)), // Allow slightly future for flexibility
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // --- Manual Product Sales Management ---
  void _addManualSalesEntry() {
    setState(() {
      _manualSalesEntries.add({
        'product_id': null,
        'quantity_sold': null,
      });
    });
  }

  void _removeManualSalesEntry(int index) {
    setState(() {
      final productId = _manualSalesEntries[index]['product_id'];
      if (productId != null) {
        _selectedManualProductIds.remove(productId);
      }
      _manualSalesEntries.removeAt(index);
      // Dispose controller if it exists
      final controller = _manualProductQtyControllers.remove(productId);
      controller?.dispose();
    });
  }

  // --- Cocktail Sales Management ---
  void _addCocktailSalesEntry() {
    setState(() {
      _cocktailSalesEntries.add({
        'recipe_id': null,
        'quantity_sold': null,
      });
    });
  }

  void _removeCocktailSalesEntry(int index) {
    setState(() {
      final recipeId = _cocktailSalesEntries[index]['recipe_id'];
      if (recipeId != null) {
        _selectedCocktailRecipeIds.remove(recipeId);
      }
      _cocktailSalesEntries.removeAt(index);
      // Dispose controller if it exists
      final controller = _cocktailQtyControllers.remove(recipeId);
      controller?.dispose();
    });
  }

  // --- Submit All Sales ---
  Future<void> _submitAllSales() async {
    // Collect data from controllers and entries
    final List<Map<String, dynamic>> finalManualSales = [];
    for (var entry in _manualSalesEntries) {
      if (entry['product_id'] != null && _manualProductQtyControllers[entry['product_id']]?.text.isNotEmpty == true) {
        finalManualSales.add({
          'product_id': entry['product_id'],
          'quantity_sold': double.tryParse(_manualProductQtyControllers[entry['product_id']]!.text) ?? 0.0,
        });
      }
    }

    final List<Map<String, dynamic>> finalCocktailSales = [];
    for (var entry in _cocktailSalesEntries) {
      if (entry['recipe_id'] != null && _cocktailQtyControllers[entry['recipe_id']]?.text.isNotEmpty == true) {
        finalCocktailSales.add({
          'recipe_id': entry['recipe_id'],
          'quantity_sold': int.tryParse(_cocktailQtyControllers[entry['recipe_id']]!.text) ?? 0,
        });
      }
    }

    if (finalManualSales.isEmpty && finalCocktailSales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add some sales to submit.')),
      );
      return;
    }

    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    try {
      await inventoryProvider.submitSales(
        salesDate: _selectedDate,
        manualProductSales: finalManualSales,
        cocktailSales: finalCocktailSales,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sales for ${DateFormat('yyyy-MM-dd').format(_selectedDate)} submitted successfully!')),
      );
      Navigator.of(context).pop(); // Go back after success
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting sales: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  void dispose() {
    _manualProductQtyControllers.forEach((id, controller) => controller.dispose());
    _cocktailQtyControllers.forEach((id, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Sales'),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Date Picker ---
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sales Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () => _selectDate(context),
                    ),
                  ],
                ),
                const Divider(height: 30),

                // --- Manual Product Sales ---
                Text('Manual Product Sales', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _manualSalesEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _manualSalesEntries[index];
                    final productId = entry['product_id'];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              value: productId,
                              hint: const Text('Select Product'),
                              decoration: const InputDecoration(border: OutlineInputBorder()),
                              items: _availableProducts
                                  .where((p) => !_selectedManualProductIds.contains(p.id) || p.id == productId)
                                  .map((product) => DropdownMenuItem(
                                        value: product.id,
                                        child: Text('${product.name} (${product.unitOfMeasure})'),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  if (productId != null) {
                                    _selectedManualProductIds.remove(productId);
                                  }
                                  entry['product_id'] = value;
                                  if (value != null) {
                                    _selectedManualProductIds.add(value);
                                    // Initialize controller if it doesn't exist
                                    _manualProductQtyControllers.putIfAbsent(value, () => TextEditingController());
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _manualProductQtyControllers[productId],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty Sold',
                                border: OutlineInputBorder(),
                              ),
                              enabled: productId != null, // Only enabled if product is selected
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle),
                            onPressed: () => _removeManualSalesEntry(index),
                            color: Colors.red,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Product Sale'),
                    onPressed: _addManualSalesEntry,
                  ),
                ),
                const Divider(height: 30),

                // --- Cocktail Sales ---
                Text('Cocktail Sales', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cocktailSalesEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _cocktailSalesEntries[index];
                    final recipeId = entry['recipe_id'];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              value: recipeId,
                              hint: const Text('Select Recipe'),
                              decoration: const InputDecoration(border: OutlineInputBorder()),
                              items: _availableRecipes
                                  .where((r) => !_selectedCocktailRecipeIds.contains(r.id) || r.id == recipeId)
                                  .map((recipe) => DropdownMenuItem(
                                        value: recipe.id,
                                        child: Text(recipe.name),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  if (recipeId != null) {
                                    _selectedCocktailRecipeIds.remove(recipeId);
                                  }
                                  entry['recipe_id'] = value;
                                  if (value != null) {
                                    _selectedCocktailRecipeIds.add(value);
                                    _cocktailQtyControllers.putIfAbsent(value, () => TextEditingController());
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _cocktailQtyControllers[recipeId],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Qty Sold',
                                border: OutlineInputBorder(),
                              ),
                              enabled: recipeId != null,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle),
                            onPressed: () => _removeCocktailSalesEntry(index),
                            color: Colors.red,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Cocktail Sale'),
                    onPressed: _addCocktailSalesEntry,
                  ),
                ),
                const Divider(height: 30),

                Center(
                  child: ElevatedButton(
                    onPressed: _submitAllSales,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Submit All Sales'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}