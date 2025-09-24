// mobile_app/lib/screens/location_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import 'product_list_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class LocationListScreen extends StatefulWidget {
  const LocationListScreen({super.key});

  @override
  State<LocationListScreen> createState() => _LocationListScreenState();
}

class _LocationListScreenState extends State<LocationListScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch locations when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InventoryProvider>(context, listen: false).fetchLocations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location for Count'),
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
          if (inventoryProvider.locations.isEmpty) {
            return const Center(
              child: Text(
                'No locations found. Please add locations in the web portal.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: inventoryProvider.locations.length,
            itemBuilder: (context, index) {
              final location = inventoryProvider.locations[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.green),
                  title: Text(location.name),
                  subtitle: Text('ID: ${location.id}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // Navigate to the ProductListScreen for the selected location
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => ProductListScreen(location: location),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}