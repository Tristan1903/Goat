// mobile_app/lib/screens/add_edit_product_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class AddEditProductScreen extends StatefulWidget {
  final Product? product; // Null for add, non-null for edit

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _unitOfMeasureController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _productNumberController = TextEditingController();

  bool _isEditing = false; // True if editing an existing product

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _isEditing = true;
      _nameController.text = widget.product!.name;
      _typeController.text = widget.product!.type;
      _unitOfMeasureController.text = widget.product!.unitOfMeasure;
      _unitPriceController.text = widget.product!.unitPrice?.toString() ?? '';
      _productNumberController.text = widget.product!.productNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _unitOfMeasureController.dispose();
    _unitPriceController.dispose();
    _productNumberController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
      try {
        if (_isEditing) {
          await inventoryProvider.updateProduct(
            widget.product!.id!,
            name: _nameController.text,
            type: _typeController.text,
            unitOfMeasure: _unitOfMeasureController.text,
            unitPrice: double.tryParse(_unitPriceController.text),
            productNumber: _productNumberController.text.isEmpty ? null : _productNumberController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product "${_nameController.text}" updated successfully!')),
          );
        } else {
          await inventoryProvider.addProduct(
            name: _nameController.text,
            type: _typeController.text,
            unitOfMeasure: _unitOfMeasureController.text,
            unitPrice: double.tryParse(_unitPriceController.text),
            productNumber: _productNumberController.text.isEmpty ? null : _productNumberController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product "${_nameController.text}" added successfully!')),
          );
        }
        Navigator.of(context).pop(); // Go back to manage products list
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'Add New Product'),
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
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a product name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _typeController,
                    decoration: const InputDecoration(
                      labelText: 'Product Type',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a product type (e.g., Beer, Wine).';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unitOfMeasureController,
                    decoration: const InputDecoration(
                      labelText: 'Unit of Measure (e.g., EA, kg, L)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a unit of measure.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _productNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Product # (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    // No validator needed as it's optional
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unitPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Unit Price (Optional)',
                      prefixText: 'R',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        if (double.tryParse(value) == null || double.tryParse(value)! < 0) {
                          return 'Please enter a valid non-negative number for price.';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: inventoryProvider.isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: inventoryProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEditing ? 'Update Product' : 'Add Product'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}