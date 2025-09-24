// mobile_app/lib/screens/historical_variance_chart_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../models/product.dart'; // To get product name from selectedProduct
import '../widgets/home_button.dart';

class HistoricalVarianceChartScreen extends StatefulWidget {
  const HistoricalVarianceChartScreen({super.key});

  @override
  State<HistoricalVarianceChartScreen> createState() => _HistoricalVarianceChartScreenState();
}

class _HistoricalVarianceChartScreenState extends State<HistoricalVarianceChartScreen> {
  Product? _selectedProduct;
  List<Product> _allProducts = []; // For the product dropdown
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAllProducts();
    });
  }

  Future<void> _fetchAllProducts() async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    await inventoryProvider.fetchAllProducts();
    setState(() {
      _allProducts = inventoryProvider.allProducts;
    });
  }

  Future<void> _fetchHistoricalData() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product first.')),
      );
      return;
    }
    await Provider.of<InventoryProvider>(context, listen: false).fetchHistoricalVarianceData(_selectedProduct!.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historical Variance'),
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

          final historicalData = inventoryProvider.historicalVarianceData;
          final List<String> labels = (historicalData['labels'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
          final List<double?> dataPoints = (historicalData['data'] as List<dynamic>?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [];


          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButtonFormField<Product>(
                  value: _selectedProduct,
                  hint: const Text('Select Product to Analyze'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: _allProducts.map((product) => DropdownMenuItem(
                        value: product,
                        child: Text('${product.name} (${product.unitOfMeasure})'),
                      ))
                      .toList(),
                  onChanged: (Product? newValue) {
                    setState(() {
                      _selectedProduct = newValue;
                    });
                    if (newValue != null) {
                      _fetchHistoricalData(); // Fetch data when product is selected
                    }
                  },
                ),
              ),
              if (_selectedProduct != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Last 30 Days Variance for ${_selectedProduct!.name}', style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _fetchHistoricalData,
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Expanded(
                child: historicalData.isEmpty || labels.isEmpty || dataPoints.isEmpty
                    ? Center(
                        child: Text(
                          _selectedProduct == null
                              ? 'Select a product to view its historical variance.'
                              : 'No historical variance data for this product.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: labels.length,
                        itemBuilder: (context, index) {
                          final date = labels[index];
                          final variance = dataPoints[index];
                          Color varianceColor = Colors.grey;
                          String varianceText = 'N/A (No Count)';

                          if (variance != null) {
                            if (variance > 0) {
                              varianceColor = Colors.green;
                              varianceText = '+${variance.toStringAsFixed(2)}';
                            } else if (variance < 0) {
                              varianceColor = Colors.red;
                              varianceText = variance.toStringAsFixed(2);
                            } else {
                              varianceColor = Colors.blueGrey;
                              varianceText = '0.00';
                            }
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            elevation: 1,
                            child: ListTile(
                              title: Text(DateFormat('yyyy-MM-dd').format(DateTime.parse(date))),
                              trailing: Text(
                                varianceText,
                                style: TextStyle(color: varianceColor, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              // TODO: Here you'd integrate a charting library for a proper chart view
                              // For example, using a simple bar or line chart from fl_chart
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