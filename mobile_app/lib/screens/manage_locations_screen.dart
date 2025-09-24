// mobile_app/lib/screens/manage_locations_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../providers/inventory_provider.dart';
import 'add_edit_location_screen.dart'; // We will create this next
import 'assign_products_to_location_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class ManageLocationsScreen extends StatefulWidget {
  const ManageLocationsScreen({super.key});

  @override
  State<ManageLocationsScreen> createState() => _ManageLocationsScreenState();
}

class _ManageLocationsScreenState extends State<ManageLocationsScreen> {
  String _searchQuery = ''; // For searching locations

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InventoryProvider>(context, listen: false).fetchLocations();
    });
  }

  // Filter locations based on search query
  List<Location> _getFilteredLocations(List<Location> allLocations) {
    if (_searchQuery.isEmpty) {
      return allLocations;
    } else {
      return allLocations
          .where((location) => location.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  // --- Delete Location Action ---
  Future<void> _deleteLocation(int locationId, String locationName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete location "$locationName"? This action cannot be undone and will unassign all products.'),
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
        await inventoryProvider.deleteLocation(locationId, locationName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location "$locationName" deleted successfully!')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting location: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Locations'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => const AddEditLocationScreen(), // Navigate to add location screen
                ),
              );
            },
            tooltip: 'Add New Location',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<InventoryProvider>(context, listen: false).fetchLocations(),
            tooltip: 'Refresh Locations',
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
          if (inventoryProvider.locations.isEmpty) {
            return const Center(
              child: Text(
                'No locations found. Add one using the + button.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredLocations = _getFilteredLocations(inventoryProvider.locations);

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Search Locations',
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
                  itemCount: filteredLocations.length,
                  itemBuilder: (context, index) {
                    final location = filteredLocations[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      elevation: 2,
                      child: ListTile(
                        title: Text(location.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        // Subtitle could show number of assigned products, if API provides that
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.assignment, color: Colors.blue),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => AssignProductsToLocationScreen(location: location), // Navigate to assign products
                                  ),
                                );
                              },
                              tooltip: 'Assign Products',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => AddEditLocationScreen(location: location), // Navigate to edit screen
                                  ),
                                );
                              },
                              tooltip: 'Edit Location',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteLocation(location.id!, location.name),
                              tooltip: 'Delete Location',
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