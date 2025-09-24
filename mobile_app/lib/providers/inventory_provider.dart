import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/location.dart';
import '../models/product.dart';
import '../models/recipe.dart';

class InventoryProvider with ChangeNotifier {
  final AuthApi _authApi;
  List<Map<String, dynamic>> _dailySummaryReportData = [];
  List<Map<String, dynamic>> _inventoryLogData = [];      
  List<Location> _locations = [];
  List<Product> _productsInSelectedLocation = [];
  List<Product> _allProducts = []; 
  List<Recipe> _allRecipes = []; 
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> getAllProducts = [];       
  Map<String, dynamic> _historicalVarianceData = {};  
  List<Map<String, dynamic>> _varianceReportData = [];       

  InventoryProvider(this._authApi);

  List<Location> get locations => _locations;
  List<Product> get productsInSelectedLocation => _productsInSelectedLocation;
  List<Product> get allProducts => _allProducts; 
  List<Recipe> get allRecipes => _allRecipes;     
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get dailySummaryReportData => _dailySummaryReportData; 
  List<Map<String, dynamic>> get inventoryLogData => _inventoryLogData;             
  List<Map<String, dynamic>> get varianceReportData => _varianceReportData;           
  Map<String, dynamic> get historicalVarianceData => _historicalVarianceData;


  AuthApi get authApi => _authApi; // Expose AuthApi for other screens

  // --- Fetch All Locations ---
  Future<void> fetchLocations() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // `_authApi.getLocations()` now returns `List<Location>` directly.
      // So, assign it directly to `_locations` (which is `List<Location>`).
      _locations = await _authApi.getLocations(); // <--- FIX HERE: Direct assignment
      // The old line `_locations = data.map((json) => Location.fromJson(json)).toList();` is no longer needed.
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchLocations: $_errorMessage'); // Add print for debugging
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Products for a Specific Location and Merge BOD Data ---
  Future<void> fetchProductsForLocation(int locationId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Fetch generic product data for the location
      final List<Product> products = await _authApi.getProductsByLocation(locationId);
      final List<Map<String, dynamic>> bodJson = await _authApi.getBodForToday();
      Map<int, double> bodMap = {
        for (var bodItem in bodJson)
          (bodItem['product_id'] as int): (bodItem['bod_amount'] as num?)?.toDouble() ?? 0.0,
      };

      // 3. Fetch latest counts for this location for today
      final List<Map<String, dynamic>> latestCountsJson = await _authApi.getLatestCountsForLocation(locationId);
      Map<int, Map<String, dynamic>> latestCountsMap = {};
      for (var countItem in latestCountsJson) {
        final productId = countItem['product_id'];
        if (productId is int) {
          latestCountsMap[productId] = countItem;
        }
      }

      // --- MODIFIED: 4. Merge all data into products with new fields ---
      _productsInSelectedLocation = products.map((product) {
        product.currentBodAmount = bodMap[product.id] ?? 0.0; // This is always today's BOD

        final latestCountData = latestCountsMap[product.id];
        if (latestCountData != null) {
          // If a count already exists, populate these for correction mode
          product.currentCountAmount = (latestCountData['amount'] as num?)?.toDouble(); // The actual last submitted count
          product.countComment = latestCountData['comment'] as String?;
          product.lastCountType = latestCountData['count_type'] as String?; // Store the type of the last count
          // The `expected_amount` from the latestCountData is essentially the BOD from when that count was made.
          // We can call it `referenceAmount` or similar if needed for display.
          // For now, product.currentBodAmount holds TODAY's BOD, and currentCountAmount holds LAST_COUNT.
        } else {
          // If no count exists yet, inputs should be blank for a First Count.
          product.currentCountAmount = null; // Explicitly null for First Count mode
          product.countComment = null;
          product.lastCountType = null;
        }
        return product;
      }).toList();

      // Sort products, e.g., by type then by name
      _productsInSelectedLocation.sort((a, b) {
        int typeCompare = a.type.compareTo(b.type);
        if (typeCompare != 0) return typeCompare;
        return a.name.compareTo(b.name);
      });

    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Update a product's count locally ---
  void updateProductCount(int productId, double amount, String? comment) {
    final index = _productsInSelectedLocation.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _productsInSelectedLocation[index].currentCountAmount = amount;
      _productsInSelectedLocation[index].countComment = comment;
      notifyListeners();
    }
  }

  // --- Submit Counts to Backend ---
  Future<void> submitCounts(int locationId, String countType) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Filter products that actually have a count value entered
      final productsToSubmit = _productsInSelectedLocation
          .where((p) => p.currentCountAmount != null)
          .map((p) => {
                'product_id': p.id,
                'amount': p.currentCountAmount!,
                'comment': p.countComment,
              })
          .toList();

      if (productsToSubmit.isEmpty) {
        throw Exception("No count amounts entered to submit.");
      }

      await _authApi.submitCount(
        locationId: locationId,
        countType: countType,
        productsToCount: productsToSubmit,
      );
      _errorMessage = null; // Clear any previous errors on successful submission
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Call this method to clear product data when leaving a count screen
  void clearProductsInSelectedLocation() {
    _productsInSelectedLocation = [];
    notifyListeners();
  }
  
  Future<void> submitBodStock(List<Product> productsToSubmit) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final productsStockData = productsToSubmit
          .where((p) => p.currentCountAmount != null) // Only submit if a value is set
          .map((p) => {
                'product_id': p.id,
                'amount': p.currentCountAmount!, // Using currentCountAmount for new BOD value
              })
          .toList();

      if (productsStockData.isEmpty) {
        throw Exception("No stock amounts entered to submit.");
      }

      await _authApi.submitBodStock(productsStockData);
      _errorMessage = null; // Clear any previous errors on successful submission
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitBodStock: $_errorMessage'); // Debug print
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Request Recount ---
  Future<void> requestRecount({int? productId, int? locationId}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authApi.requestRecount(productId: productId, locationId: locationId);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in requestRecount: $_errorMessage'); // Debug print
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // `_authApi.getAllProducts()` now returns `List<Product>` directly.
      // So, assign it directly to `_allProducts` (which is `List<Product>`).
      _allProducts = await _authApi.getAllProducts(); // <--- FIX HERE: Direct assignment
      // The old line `_allProducts = data.map((json) => Product.fromJson(json)).toList();` is no longer needed.
      _allProducts.sort((a, b) => a.name.compareTo(b.name)); // Sort alphabetically
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchAllProducts: $_errorMessage'); // Add print for debugging
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Fetch All Recipes (for dropdowns) ---
  Future<void> fetchAllRecipes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _allRecipes = await _authApi.getAllRecipes();
      _allRecipes.sort((a, b) => a.name.compareTo(b.name)); // Sort alphabetically
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchAllRecipes: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Submit Sales ---
  Future<void> submitSales({
    required DateTime salesDate,
    required List<Map<String, dynamic>> manualProductSales,
    required List<Map<String, dynamic>> cocktailSales,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitSales(
        salesDate: salesDate,
        manualProductSales: manualProductSales,
        cocktailSales: cocktailSales,
      );
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitSales: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Submit Delivery ---
  Future<void> submitDelivery({
    required int productId,
    required double quantity,
    required DateTime deliveryDate,
    String? comment,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitDelivery(
        productId: productId,
        quantity: quantity,
        deliveryDate: deliveryDate,
        comment: comment,
      );
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitDelivery: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDailySummaryReport(DateTime date) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dailySummaryReportData = await _authApi.getDailySummaryReport(date);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchDailySummaryReport: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Fetch Inventory Log ---
  Future<void> fetchInventoryLog(DateTime startDate, DateTime endDate) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _inventoryLogData = await _authApi.getInventoryLog(startDate, endDate);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchInventoryLog: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> fetchVarianceReport(DateTime date) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _varianceReportData = await _authApi.getVarianceReport(date);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchVarianceReport: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Fetch Historical Variance Data ---
  Future<void> fetchHistoricalVarianceData(int productId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _historicalVarianceData = await _authApi.getVarianceHistory(productId);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchHistoricalVarianceData: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Submit Variance Explanation ---
  Future<void> submitVarianceExplanation(int countId, String reason) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.submitVarianceExplanation(countId, reason);
      _errorMessage = null; // Clear error on success
      // No direct data refresh needed for this provider, the report screen will refetch.
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitVarianceExplanation: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> submitAllPrices(List<Product> productsToSubmit) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final productPricesData = productsToSubmit
          .where((p) => p.unitPrice != null)
          .map((p) => { // <--- MODIFIED: Ensure this correctly creates a Map
                'product_id': p.id,
                'unit_price': p.unitPrice,
              })
          .toList();

      if (productPricesData.isEmpty) {
        throw Exception("No product prices entered to submit.");
      }

      await _authApi.submitAllPrices(productPricesData); // <--- Call the new method
      _errorMessage = null;
      await fetchAllProducts();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in submitAllPrices: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

Future<void> addProduct({
    required String name,
    required String type,
    required String unitOfMeasure,
    double? unitPrice,
    String? productNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _authApi.addProduct(
        name: name,
        type: type,
        unitOfMeasure: unitOfMeasure,
        unitPrice: unitPrice,
        productNumber: productNumber,
      );
      _errorMessage = null;
      await fetchAllProducts(); // Refresh list after adding
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Get Product Details (for editing) ---
  Future<Product?> getProductDetails(int productId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // --- MODIFIED: Directly return the Product object from AuthApi ---
      return await _authApi.getProductDetails(productId); // `_authApi` already returns a `Product`
      // --- END MODIFIED ---
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in getProductDetails: $_errorMessage'); // Add print for debugging
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Update Product ---
  Future<void> updateProduct(int productId, {
    required String name,
    required String type,
    required String unitOfMeasure,
    double? unitPrice,
    String? productNumber,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.updateProduct(
        productId,
        name: name,
        type: type,
        unitOfMeasure: unitOfMeasure,
        unitPrice: unitPrice,
        productNumber: productNumber,
      );
      _errorMessage = null;
      await fetchAllProducts(); // Refresh list after updating
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Delete Product ---
  Future<void> deleteProduct(int productId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteProduct(productId);
      _errorMessage = null;
      await fetchAllProducts(); // Refresh list after deleting
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLocation(String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _authApi.addLocation(name);
      _errorMessage = null;
      await fetchLocations(); // Refresh list after adding
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Get Location Details (for editing) ---
  // This returns a Map<String, dynamic> because it includes assigned products
  Future<Map<String, dynamic>?> getLocationDetails(int locationId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final data = await _authApi.getLocationDetails(locationId);
      return data;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Update Location ---
  Future<void> updateLocation(int locationId, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.updateLocation(locationId, name);
      _errorMessage = null;
      await fetchLocations(); // Refresh list after updating
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Delete Location ---
  Future<void> deleteLocation(int locationId, String locationName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteLocation(locationId);
      _errorMessage = null;
      await fetchLocations(); // Refresh list after deleting
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- NEW: Assign Products to Location ---
  Future<void> assignProductsToLocation(int locationId, List<int> productIds) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.assignProductsToLocation(locationId, productIds);
      _errorMessage = null;
      // After assigning products, you might want to refresh location data on dashboard
      await fetchLocations();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}