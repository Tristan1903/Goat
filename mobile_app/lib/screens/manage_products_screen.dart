// mobile_app/lib/screens/manage_products_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import 'add_edit_product_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class ManageProductsScreen extends StatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  State<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

class _ManageProductsScreenState extends State<ManageProductsScreen> {
  String _searchQuery = ''; // For searching products

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InventoryProvider>(context, listen: false).fetchAllProducts();
    });
  }

  // Filter products based on search query
  List<Product> _getFilteredProducts(List<Product> allProducts) {
    if (_searchQuery.isEmpty) {
      return allProducts;
    } else {
      return allProducts
          .where((product) =>
              product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (product.productNumber?.toLowerCase() ?? '').contains(_searchQuery.toLowerCase()) ||
              product.type.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  // --- Delete Product Action ---
  Future<void> _deleteProduct(int productId, String productName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete product "$productName"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Delete'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
      try {
        await inventoryProvider.deleteProduct(productId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product "$productName" deleted successfully!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Products'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => const AddEditProductScreen(), // Navigate to add product screen
                ),
              );
            },
            tooltip: 'Add New Product',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<InventoryProvider>(context, listen: false).fetchAllProducts(),
            tooltip: 'Refresh Products',
          ),
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
          if (inventoryProvider.allProducts.isEmpty) {
            return const Center(
              child: Text(
                'No products found. Add one using the + button.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredProducts = _getFilteredProducts(inventoryProvider.allProducts);

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(8.0),
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      elevation: 2,
                      child: ListTile(
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${product.type} | #${product.productNumber ?? 'N/A'} | R${product.unitPrice?.toStringAsFixed(2) ?? 'N/A'} (${product.unitOfMeasure})'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => AddEditProductScreen(product: product), // Navigate to edit screen
                                  ),
                                );
                              },
                              tooltip: 'Edit Product',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteProduct(product.id!, product.name),
                              tooltip: 'Delete Product',
                            ),
                          ],
                        ),
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