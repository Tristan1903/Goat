// mobile_app/lib/screens/submit_delivery_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/home_button.dart';

class SubmitDeliveryScreen extends StatefulWidget {
  const SubmitDeliveryScreen({super.key});

  @override
  State<SubmitDeliveryScreen> createState() => _SubmitDeliveryScreenState();
}

class _SubmitDeliveryScreenState extends State<SubmitDeliveryScreen> {
  DateTime _selectedDeliveryDate = DateTime.now();
  Product? _selectedProduct;
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  List<Product> _availableProducts = [];

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    await inventoryProvider.fetchAllProducts();
    setState(() {
      _availableProducts = inventoryProvider.allProducts;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeliveryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDeliveryDate) {
      setState(() {
        _selectedDeliveryDate = picked;
      });
    }
  }

  Future<void> _submitDelivery() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product.')),
      );
      return;
    }
    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive quantity.')),
      );
      return;
    }

    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    try {
      await inventoryProvider.submitDelivery(
        productId: _selectedProduct!.id!,
        quantity: quantity,
        deliveryDate: _selectedDeliveryDate,
        comment: _commentController.text.isEmpty ? null : _commentController.text,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery logged successfully!')),
      );
      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting delivery: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log New Delivery'),
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
                // --- Delivery Date ---
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Delivery Date: ${DateFormat('yyyy-MM-dd').format(_selectedDeliveryDate)}',
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

                // --- Product Dropdown ---
                DropdownButtonFormField<Product>(
                  value: _selectedProduct,
                  hint: const Text('Select Product'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: _availableProducts.map((product) => DropdownMenuItem(
                        value: product,
                        child: Text('${product.name} (${product.unitOfMeasure})'),
                      ))
                      .toList(),
                  onChanged: (Product? newValue) {
                    setState(() {
                      _selectedProduct = newValue;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // --- Quantity Input ---
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantity Delivered',
                    border: const OutlineInputBorder(),
                    suffixText: _selectedProduct?.unitOfMeasure ?? 'Units',
                  ),
                ),
                const SizedBox(height: 16),

                // --- Comment Input ---
                TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    labelText: 'Comment (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 30),

                // --- Submit Button ---
                Center(
                  child: ElevatedButton(
                    onPressed: inventoryProvider.isLoading ? null : _submitDelivery,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Log Delivery'),
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