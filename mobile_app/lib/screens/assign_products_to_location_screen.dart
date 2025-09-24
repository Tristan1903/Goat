// mobile_app/lib/screens/assign_products_to_location_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class AssignProductsToLocationScreen extends StatefulWidget {
  final Location location;

  const AssignProductsToLocationScreen({super.key, required this.location});

  @override
  State<AssignProductsToLocationScreen> createState() => _AssignProductsToLocationScreenState();
}

class _AssignProductsToLocationScreenState extends State<AssignProductsToLocationScreen> {
  // Use a Set to efficiently track selected product IDs
  final Set<int> _selectedProductIds = {};
  List<Product> _allProducts = []; // All available products for selection
  String _searchQuery = ''; // For searching products
  String _typeFilter = 'All'; // For filtering by product type

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDataAndAssignedProducts();
    });
  }

  Future<void> _fetchDataAndAssignedProducts() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    // Fetch all products
    await inventoryProvider.fetchAllProducts();
    // Fetch details for the specific location, which includes its current assignments
    final locationDetails = await inventoryProvider.getLocationDetails(widget.location.id!);

    setState(() {
      _allProducts = inventoryProvider.allProducts;
      if (locationDetails != null && locationDetails['assigned_products'] != null) {
        final List<dynamic> assignedJson = locationDetails['assigned_products'];
        for (var productJson in assignedJson) {
          _selectedProductIds.add(productJson['id'] as int);
        }
      }
    });
  }

  // Filter products based on search query and type filter
  List<Product> _getFilteredProducts(List<Product> allProducts) {
    List<Product> filtered = allProducts.where((product) {
      final nameMatch = product.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final typeMatch = _typeFilter == 'All' || product.type.toLowerCase() == _typeFilter.toLowerCase();
      return nameMatch && typeMatch;
    }).toList();
    // Sort alphabetically for consistent display
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  Future<void> _submitAssignments() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    try {
      await inventoryProvider.assignProductsToLocation(
        widget.location.id!,
        _selectedProductIds.toList(), // Convert Set to List for API
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Products assigned to "${widget.location.name}" successfully!')),
      );
      Navigator.of(context).pop(); // Go back to manage locations list
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error assigning products: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get distinct product types for the filter dropdown
    final List<String> uniqueTypes = ['All'] + _allProducts.map((p) => p.type).toSet().toList();
    uniqueTypes.sort(); // Sort types alphabetically

    return Scaffold(
      appBar: AppBar(
        title: Text('Assign Products to ${widget.location.name}'),
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
          if (_allProducts.isEmpty) {
            return const Center(
              child: Text(
                'No products available to assign. Please add products first.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredProducts = _getFilteredProducts(_allProducts);

          return Column(
            children: [
              // Search and Filter Row
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: 'Search Products',
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
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _typeFilter,
                        icon: const Icon(Icons.filter_list),
                        onChanged: (String? newValue) {
                          setState(() {
                            _typeFilter = newValue ?? 'All';
                          });
                        },
                        items: uniqueTypes.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Product List with Checkboxes
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      elevation: 1,
                      child: CheckboxListTile(
                        title: Text(product.name),
                        subtitle: Text('${product.type} | #${product.productNumber ?? 'N/A'}'),
                        value: _selectedProductIds.contains(product.id),
                        onChanged: (bool? newValue) {
                          setState(() {
                            if (newValue == true) {
                              _selectedProductIds.add(product.id!);
                            } else {
                              _selectedProductIds.remove(product.id!);
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: inventoryProvider.isLoading ? null : _submitAssignments,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: inventoryProvider.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Assignments'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}