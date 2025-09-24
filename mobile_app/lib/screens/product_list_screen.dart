import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location.dart';
import '../models/product.dart';
import '../providers/inventory_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/home_button.dart';

class ProductListScreen extends StatefulWidget {
  final Location location;

  const ProductListScreen({super.key, required this.location});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final Map<int, TextEditingController> _countControllers = {};
  final Map<int, TextEditingController> _commentControllers = {};
  bool _showAllProducts = true;
  bool _isFirstCountDoneForLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InventoryProvider>(context, listen: false)
          .fetchProductsForLocation(widget.location.id)
          .then((_) {
        _checkFirstCountStatus();
        _initializeControllers();
      });
    });
  }

  void _checkFirstCountStatus() {
    // Determine if any count has been submitted for this location (for the current day)
    // If the location's status from DashboardProvider indicates 'counted' or 'corrected',
    // then a first count is considered done.
    if (widget.location.status == 'counted' || widget.location.status == 'corrected') {
      setState(() {
        _isFirstCountDoneForLocation = true;
      });
    } else {
      setState(() {
        _isFirstCountDoneForLocation = false;
      });
    }
  }

  void _initializeControllers() {
    final products = Provider.of<InventoryProvider>(context, listen: false).productsInSelectedLocation;
    for (var product in products) {
      // --- MODIFIED: Initializing controllers ---
      // If in correction mode, pre-fill with the last submitted count.
      // If in first count mode, leave blank.
      String initialCountText = _isFirstCountDoneForLocation
          ? (product.currentCountAmount?.toStringAsFixed(2) ?? '') // Last submitted count
          : ''; // Blank for first count

      String initialCommentText = _isFirstCountDoneForLocation
          ? (product.countComment ?? '')
          : ''; // Blank for first count

      _countControllers[product.id!] = TextEditingController(text: initialCountText);
      _commentControllers[product.id!] = TextEditingController(text: initialCommentText);
      // --- END MODIFIED ---

      _countControllers[product.id!]?.addListener(() {
        final amount = double.tryParse(_countControllers[product.id!]!.text);
        Provider.of<InventoryProvider>(context, listen: false,).updateProductCount(
          product.id!,
          amount ?? 0.0,
          _commentControllers[product.id!]!.text,
        );
      });
      _commentControllers[product.id!]?.addListener(() {
        final amount = double.tryParse(_countControllers[product.id!]!.text);
        Provider.of<InventoryProvider>(context, listen: false,).updateProductCount(
          product.id!,
          amount ?? 0.0,
          _commentControllers[product.id!]!.text,
        );
      });
    }
  }

  @override
  void dispose() {
    _countControllers.forEach((key, controller) => controller.dispose());
    _commentControllers.forEach((key, controller) => controller.dispose());
    Provider.of<InventoryProvider>(context, listen: false).clearProductsInSelectedLocation();
    super.dispose();
  }

  void _submitCounts(String countType) async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    setState(() => _showAllProducts = true);

    try {
      await inventoryProvider.submitCounts(widget.location.id, countType);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$countType submitted successfully!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _requestRecount({int? productId, int? locationId}) async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    try {
      await inventoryProvider.requestRecount(productId: productId, locationId: locationId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recount requested successfully! Staff notified.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error requesting recount: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  List<Product> _getFilteredProducts(List<Product> allProducts) {
    if (_showAllProducts) {
      return allProducts;
    } else {
      return allProducts.where((product) {
        final enteredAmountText = _countControllers[product.id!]?.text ?? '';
        final enteredAmount = double.tryParse(enteredAmountText);
        final hasComment = (_commentControllers[product.id!]?.text ?? '').isNotEmpty;

        // --- MODIFIED: Filtering logic based on mode ---
        if (!_isFirstCountDoneForLocation) { // In First Count mode
          // Show only if amount is entered or comment exists
          return (enteredAmount != null && enteredAmount != 0.0) || hasComment;
        } else { // In Corrections/Recount mode
          final originalCountReference = product.currentCountAmount; // This is the last submitted count
          // Show if entered amount is different from the original reference, or comment exists
          return (enteredAmount != null && enteredAmount != originalCountReference) || hasComment;
        }
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool canRequestRecount = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.location.name} Count'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          Row(
            children: [
              Text('Show All', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
              Switch(
                value: _showAllProducts,
                onChanged: (value) {
                  setState(() {
                    _showAllProducts = value;
                  });
                },
                activeColor: Colors.white,
                inactiveThumbColor: Colors.grey[400],
                inactiveTrackColor: Colors.grey[600],
              ),
              if (canRequestRecount)
                IconButton(
                  icon: const Icon(Icons.redo),
                  tooltip: 'Request Recount for all products in this location',
                  onPressed: () => _requestRecount(locationId: widget.location.id),
                ),
            ],
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
          if (inventoryProvider.productsInSelectedLocation.isEmpty) {
            return const Center(
              child: Text(
                'No products assigned to this location. Please assign products in the web portal.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final displayedProducts = _getFilteredProducts(inventoryProvider.productsInSelectedLocation);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: displayedProducts.length,
                  itemBuilder: (context, index) {
                    final product = displayedProducts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (canRequestRecount)
                                  IconButton(
                                    icon: const Icon(Icons.redo_outlined, size: 20),
                                    tooltip: 'Request Recount for this product',
                                    onPressed: () => _requestRecount(productId: product.id),
                                  ),
                              ],
                            ),
                            Text('Type: ${product.type} | Unit: ${product.unitOfMeasure}'),
                            Text('Product #: ${product.productNumber ?? 'N/A'}'),
                            // --- MODIFIED: BOD vs. Previous Count Display ---
                            // Always show BOD amount (today's expected starting stock)
                            Text('BOD Amount: ${product.currentBodAmount?.toStringAsFixed(2) ?? '0.00'} ${product.unitOfMeasure}'),
                            if (_isFirstCountDoneForLocation) // Only show "Previous Count" if in corrections mode
                              Text(
                                'Previous Count: ${product.currentCountAmount?.toStringAsFixed(2) ?? '0.00'} ${product.unitOfMeasure}',
                                style: const TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                              ),
                            const SizedBox(height: 10),
                            // Count Amount Input Field
                            TextField(
                              controller: _countControllers[product.id!],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Count Amount (${product.unitOfMeasure})',
                                border: const OutlineInputBorder(),
                                suffixText: product.unitOfMeasure,
                              ),
                              onChanged: (value) {
                                // Listener already attached in _initializeControllers handles the update
                              },
                            ),
                            // Comment field only visible in correction mode
                            if (_isFirstCountDoneForLocation)
                              const SizedBox(height: 10),
                            if (_isFirstCountDoneForLocation)
                              TextField(
                                controller: _commentControllers[product.id!],
                                decoration: const InputDecoration(
                                  labelText: 'Comment (Optional)',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                                onChanged: (value) {
                                  // Listener already attached in _initializeControllers handles the update
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // --- Submit Buttons for Counts ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // "Submit First Count" button only if no first count done
                    if (!_isFirstCountDoneForLocation)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: inventoryProvider.isLoading ? null : () => _submitCounts('First Count'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                          child: const Text('Submit First Count'),
                        ),
                      ),
                    // "Submit Corrections" button only if first count done
                    if (_isFirstCountDoneForLocation)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: inventoryProvider.isLoading ? null : () => _submitCounts('Corrections Count'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                          child: const Text('Submit Corrections'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}