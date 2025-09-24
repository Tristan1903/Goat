// mobile_app/lib/screens/add_edit_location_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class AddEditLocationScreen extends StatefulWidget {
  final Location? location; // Null for add, non-null for edit

  const AddEditLocationScreen({super.key, this.location});

  @override
  State<AddEditLocationScreen> createState() => _AddEditLocationScreenState();
}

class _AddEditLocationScreenState extends State<AddEditLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isEditing = false; // True if editing an existing location

  @override
  void initState() {
    super.initState();
    if (widget.location != null) {
      _isEditing = true;
      _nameController.text = widget.location!.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
      try {
        if (_isEditing) {
          await inventoryProvider.updateLocation(
            widget.location!.id!,
            _nameController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location "${_nameController.text}" updated successfully!')),
          );
        } else {
          await inventoryProvider.addLocation(
            _nameController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location "${_nameController.text}" added successfully!')),
          );
        }
        Navigator.of(context).pop(); // Go back to manage locations list
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
        title: Text(_isEditing ? 'Edit Location' : 'Add New Location'),
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
                      labelText: 'Location Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a location name.';
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
                        : Text(_isEditing ? 'Update Location' : 'Add Location'),
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