// mobile_app/lib/screens/set_bod_stock_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class SetBodStockScreen extends StatefulWidget {
  const SetBodStockScreen({super.key});

  @override
  State<SetBodStockScreen> createState() => _SetBodStockScreenState();
}

class _SetBodStockScreenState extends State<SetBodStockScreen> {
  // Use a map to store TextEditingControllers for each product by its ID
  final Map<int, TextEditingController> _stockControllers = {};
  List<Product> _allProducts = []; // To hold all products fetched initially
  bool _showAllProducts = true; // For filtering products with changed/empty values
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchProductsAndBod();
  }

  // Fetch all products and their current BOD amounts
  Future<void> _fetchProductsAndBod() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    setState(() {
      // Set loading state here, as InventoryProvider's fetchProductsForLocation does this
      // but we are directly calling BOD APIs for all products.
      // Ideally, InventoryProvider would have a `fetchAllProductsWithBod` method.
    });

    try {
      // For simplicity, let's just use the `getBodForToday` and then populate Product objects.
      // In a more robust app, InventoryProvider would manage all products separately from 'selected location' products.
      final List<Map<String, dynamic>> bodJson = await inventoryProvider.authApi.getBodForToday();
      _allProducts = bodJson.map((json) => Product.fromBodJson(json)).toList();

      // Sort products, e.g., by name
      _allProducts.sort((a, b) => a.name.compareTo(b.name));

      // Initialize controllers with fetched BOD amounts
      _allProducts.forEach((product) {
        _stockControllers[product.id!] = TextEditingController(text: product.currentBodAmount?.toStringAsFixed(2) ?? '');
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading products for BOD: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      setState(() {}); // Rebuild UI after fetching and initializing
    }
  }

  @override
  void dispose() {
    _stockControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitBodStock() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    
    // Create a list of products to submit, using the current values from controllers
    final List<Product> productsToSubmit = _allProducts.map((product) {
      final controller = _stockControllers[product.id!];
      final amount = double.tryParse(controller?.text ?? '');
      return Product(
        id: product.id!,
        name: product.name, // Keep existing product data
        type: product.type,
        unitOfMeasure: product.unitOfMeasure,
        currentCountAmount: amount, // Use this for the amount to submit
      );
    }).toList();

    try {
      await inventoryProvider.submitBodStock(productsToSubmit);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beginning of Day stock submitted successfully!')),
      );
      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting BOD stock: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  List<Product> _getFilteredProducts() {
    List<Product> filtered = _allProducts.where((product) {
      final nameMatch = product.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final numberMatch = (product.productNumber?.toLowerCase() ?? '').contains(_searchQuery.toLowerCase());

      bool showThisProduct = nameMatch || numberMatch;

      if (!_showAllProducts && showThisProduct) {
        final controller = _stockControllers[product.id!];
        final currentAmount = double.tryParse(controller?.text ?? '');
        final originalBod = product.currentBodAmount;

        // Show if current amount is different from original BOD, or if it's new (original was null)
        showThisProduct = (currentAmount != originalBod) || (currentAmount != null && originalBod == null);
      }
      return showThisProduct;
    }).toList();

    // Re-apply sorting after filtering
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _getFilteredProducts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set All BOD Stock'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: Column(
        children: [
          // Filter/Search Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search Product Name or Number',
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
          // Filter Checkbox
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Switch(
                  value: _showAllProducts,
                  onChanged: (value) {
                    setState(() {
                      _showAllProducts = value;
                    });
                  },
                ),
                const Text('Show All Products (Off: show only changed/blank)'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final product = filteredProducts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text('${product.type} | #${product.productNumber ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _stockControllers[product.id!],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Stock',
                              suffixText: product.unitOfMeasure,
                              border: const OutlineInputBorder(
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _submitBodStock,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50), // Make button full width and tall
              ),
              child: const Text('Save All BOD Stock'),
            ),
          ),
        ],
      ),
    );
  }
}