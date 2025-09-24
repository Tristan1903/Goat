// mobile_app/lib/screens/set_all_prices_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class SetAllPricesScreen extends StatefulWidget {
  const SetAllPricesScreen({super.key});

  @override
  State<SetAllPricesScreen> createState() => _SetAllPricesScreenState();
}

class _SetAllPricesScreenState extends State<SetAllPricesScreen> {
  final Map<int, TextEditingController> _priceControllers = {};
  List<Product> _allProducts = []; // To hold all products fetched initially
  bool _showAllProducts = true; // For filtering products with changed/empty values
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchProductsAndPrices();
  }

  // Fetch all products and their current prices
  Future<void> _fetchProductsAndPrices() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    await inventoryProvider.fetchAllProducts(); // Fetches all products
    setState(() {
      _allProducts = inventoryProvider.allProducts;
      // Initialize controllers with fetched unit prices
      _allProducts.forEach((product) {
        _priceControllers[product.id!] = TextEditingController(text: product.unitPrice?.toStringAsFixed(2) ?? '');
        // Attach listener to update product's unitPrice when text changes
        _priceControllers[product.id!]?.addListener(() {
          final price = double.tryParse(_priceControllers[product.id!]!.text);
          final index = _allProducts.indexWhere((p) => p.id == product.id);
          if (index != -1) {
            _allProducts[index].unitPrice = price; // Update the product object in the local list
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _priceControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _submitAllPrices() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    
    // Create a list of products to submit, using the current values from controllers
    final List<Product> productsToSubmit = _allProducts.map((product) {
      final controller = _priceControllers[product.id!];
      final price = double.tryParse(controller?.text ?? ''); // Can be null if empty string
      return Product(
        id: product.id!,
        name: product.name,
        type: product.type,
        unitOfMeasure: product.unitOfMeasure,
        unitPrice: price, // Use this for the price to submit (can be null)
      );
    }).toList();

    try {
      await inventoryProvider.submitAllPrices(productsToSubmit);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product prices submitted successfully!')),
      );
      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting product prices: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  List<Product> _getFilteredProducts() {
  List<Product> filtered = _allProducts.where((product) {
    final nameMatch = product.name.toLowerCase().contains(_searchQuery.toLowerCase());
    final numberMatch = (product.productNumber?.toLowerCase() ?? '').contains(_searchQuery.toLowerCase());

    bool showThisProduct = nameMatch || numberMatch; // Initial filter by search query

    if (!_showAllProducts && showThisProduct) {
      final controllerText = _priceControllers[product.id!]?.text ?? '';
      final trimmedControllerText = controllerText.trim();
      
      final originalPriceString = product.unitPrice == null 
                                    ? '' 
                                    : product.unitPrice!.toStringAsFixed(2);

      // A product is "changed or blank" if:
      bool isChanged = false;

      // 1. Current text is different from the original formatted string.
      if (trimmedControllerText != originalPriceString) {
        isChanged = true;
      } 
      // 2. The original price was null, but now the text is NOT empty (user entered a new price).
      else if (originalPriceString.isEmpty && trimmedControllerText.isNotEmpty) {
        isChanged = true;
      } 
      // 3. The original price was NOT null, but now the text IS empty (user cleared an existing price).
      else if (originalPriceString.isNotEmpty && trimmedControllerText.isEmpty) {
        isChanged = true;
      }
      // --- NEW CONDITION ---
      // 4. The original price was null (i.e., it's currently a placeholder/blank in the backend)
      //    This condition ensures items that need a price (were originally blank) are always shown
      //    when filtering for "changed/blank" UNLESS they've been explicitly left blank by the user
      //    and the original was also blank, in which case we rely on previous conditions.
      else if (product.unitPrice == null) { // If it had no price from the backend
        isChanged = true; // Always show it in this filter mode
      }
      // --- END NEW CONDITION ---

      showThisProduct = isChanged;
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
        title: const Text('Set All Prices'),
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
                            controller: _priceControllers[product.id!],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Price',
                              prefixText: 'R', // South African Rand
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
              onPressed: _submitAllPrices,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Save All Prices'),
            ),
          ),
        ],
      ),
    );
  }
}