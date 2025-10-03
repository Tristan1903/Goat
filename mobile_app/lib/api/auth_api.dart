// mobile_app/lib/api/auth_api.dart
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:http/http.dart' as http; // Alias 'http' for the http package
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // For secure token storage
import 'package:file_picker/file_picker.dart'; // For FilePickerResult in submitLeaveRequest
import 'package:http_parser/http_parser.dart'; // For MediaType in submitLeaveRequest

// Import all necessary models
import '../models/user.dart';
import '../models/leave_request.dart';
import '../models/recipe.dart';
import '../models/product.dart';
import '../models/location.dart';
import '../models/warning_item.dart'; // <--- NEW IMPORT
import '../models/staff_member.dart';
import '../models/schedule.dart'; // For ShiftDefinitions model
import '../models/shift_management.dart';
import '../models/booking_item.dart';
import '../models/announcement_item.dart'; // <--- NEW IMPORT
import '../models/role_item.dart';
import '../models/user_manual_section.dart';

class AuthApi {
  // IMPORTANT: This base URL needs to be correct for your testing environment.
  // For Flutter Web (PWA) running locally: 'http://localhost:5000/api/mobile'
  // For PythonAnywhere deployment: 'https://yourusername.pythonanywhere.com/api/mobile'
  final String _baseUrl = 'https://abbadon1903.pythonanywhere.com/api/mobile'; // <--- ADJUST THIS FOR YOUR LOCAL TESTING

  final _storage = const FlutterSecureStorage();

  // --- Utility for getting headers with JWT token ---
  Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    if (token == null) {
      throw Exception('No authentication token found. Please log in.');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  // --- Utility for handling API errors ---
  // This helper parses backend error messages (JSON) or provides a generic one.
  Exception _handleApiError(http.Response response) {
    String message = 'An unknown error occurred.';
    try {
      final errorData = jsonDecode(response.body);
      message = errorData['msg'] ?? message;
      if (errorData['details'] != null && (errorData['details'] is List)) {
        message += "\nDetails: ${errorData['details'].join(', ')}";
      }
    } catch (e) {
      // If response body is not JSON, use raw message
      message = response.body.isNotEmpty ? response.body : 'Server responded with unexpected format.';
    }
    print('API Error: Status ${response.statusCode}, Message: $message'); // Debug print for errors
    return Exception(message);
  }

  // =========================================================================================
  // CORE AUTHENTICATION & USER PROFILE
  // =========================================================================================

  Future<String?> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: <String, String>{'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(<String, String>{'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['access_token'];
      await _storage.write(key: 'jwt_token', value: token);
      return token;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> logout() async {
    try {
      await _storage.delete(key: 'jwt_token');
    } catch (e) {
      print('ERROR: AuthApi.logout() - Failed to delete JWT token from secure storage: $e');
      throw Exception('Failed to clear local token: $e');
    }
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<Map<String, dynamic>> getProtectedData() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/protected'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<User> fetchUserProfile(String token) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/profile'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User.fromJson(data);
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // FCM TOKEN MANAGEMENT (for PWA Push Notifications)
  // =========================================================================================

  Future<void> registerFCMToken(String fcmToken, {String? deviceInfo}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/fcm_token/register'),
      headers: await _getHeaders(),
      body: jsonEncode({'fcm_token': fcmToken, 'device_info': deviceInfo}),
    );
    if (response.statusCode == 201) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> unregisterFCMToken(String fcmToken) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/fcm_token/unregister'),
      headers: await _getHeaders(),
      body: jsonEncode({'fcm_token': fcmToken}),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // DASHBOARD DATA FETCHING
  // =========================================================================================

  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/announcements'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> announcementsData = jsonDecode(response.body);
      return announcementsData.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getLocationCountStatuses() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/location_count_statuses'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/dashboard_summary'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // INVENTORY MANAGEMENT & REPORTS
  // =========================================================================================

  Future<List<Location>> getLocations() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/locations'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> locationsData = jsonDecode(response.body);
      return locationsData.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Product>> getProductsByLocation(int locationId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/products_by_location/$locationId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> productsData = jsonDecode(response.body);
      return productsData.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Map<String, dynamic>>> getBodForToday() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/bod_for_today'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> bodData = jsonDecode(response.body);
      return bodData.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitCount({
    required int locationId,
    required String countType,
    required List<Map<String, dynamic>> productsToCount,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/submit_count'),
      headers: await _getHeaders(),
      body: jsonEncode({'location_id': locationId, 'count_type': countType, 'products_to_count': productsToCount}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Map<String, dynamic>>> getLatestCountsForLocation(int locationId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/latest_counts_for_location/$locationId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> countsData = jsonDecode(response.body);
      return countsData.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitBodStock(List<Map<String, dynamic>> productsStockData) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/submit_bod_stock'),
      headers: await _getHeaders(),
      body: jsonEncode({'products_stock_data': productsStockData}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> requestRecount({int? productId, int? locationId}) async {
    if ((productId != null && locationId != null) || (productId == null && locationId == null)) {
      throw Exception('Must provide either productId OR locationId, but not both.');
    }
    final body = {};
    if (productId != null) body['product_id'] = productId;
    else if (locationId != null) body['location_id'] = locationId;
    final response = await http.post(
      Uri.parse('$_baseUrl/request_recount'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Product>> getAllProducts() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/products'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> productsData = jsonDecode(response.body);
      return productsData.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Recipe>> getAllRecipes() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/recipes'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> recipesData = jsonDecode(response.body);
      return recipesData.map((e) => Recipe.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitSales({
    required DateTime salesDate,
    required List<Map<String, dynamic>> manualProductSales,
    required List<Map<String, dynamic>> cocktailSales,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/submit_sales'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'sales_date': salesDate.toIso8601String().substring(0, 10),
        'manual_product_sales': manualProductSales,
        'cocktail_sales': cocktailSales,
      }),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitDelivery({
    required int productId,
    required double quantity,
    required DateTime deliveryDate,
    String? comment,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/submit_delivery'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'product_id': productId,
        'quantity': quantity,
        'delivery_date': deliveryDate.toIso8601String().substring(0, 10),
        'comment': comment,
      }),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Map<String, dynamic>>> getDailySummaryReport(DateTime date) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/daily_summary_report?date=${date.toIso8601String().substring(0, 10)}'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Map<String, dynamic>>> getInventoryLog(DateTime startDate, DateTime endDate) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/inventory_log?start_date=${startDate.toIso8601String().substring(0, 10)}&end_date=${endDate.toIso8601String().substring(0, 10)}'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<List<Map<String, dynamic>>> getVarianceReport(DateTime date) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/variance_report?date=${date.toIso8601String().substring(0, 10)}'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => e as Map<String, dynamic>).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getVarianceHistory(int productId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/variance_history/$productId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitVarianceExplanation(int countId, String reason) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/variance_explanation/submit'),
      headers: await _getHeaders(),
      body: jsonEncode({'count_id': countId, 'reason': reason}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // ADMIN-LEVEL INVENTORY MANAGEMENT (Products & Locations CRUD)
  // =========================================================================================

  Future<Map<String, dynamic>> addProduct({
    required String name,
    required String type,
    required String unitOfMeasure,
    double? unitPrice,
    String? productNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/products/add'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name, 'type': type, 'unit_of_measure': unitOfMeasure, 'unit_price': unitPrice, 'product_number': productNumber}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Product> getProductDetails(int productId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/products/$productId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return Product.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> updateProduct(int productId, {
    required String name,
    required String type,
    required String unitOfMeasure,
    double? unitPrice,
    String? productNumber,
  }) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/products/$productId'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name, 'type': type, 'unit_of_measure': unitOfMeasure, 'unit_price': unitPrice, 'product_number': productNumber}),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> deleteProduct(int productId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/products/$productId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> addLocation(String name) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/locations/add'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getLocationDetails(int locationId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/locations/$locationId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> updateLocation(int locationId, String name) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/locations/$locationId'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> deleteLocation(int locationId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/locations/$locationId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> assignProductsToLocation(int locationId, List<int> productIds) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/locations/$locationId/assign_products'),
      headers: await _getHeaders(),
      body: jsonEncode({'assigned_product_ids': productIds}),
    );
    if (response.statusCode == 200) {
      return;
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitAllPrices(List<Map<String, dynamic>> productPricesData) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/set_all_prices'),
      headers: await _getHeaders(),
      body: jsonEncode({'product_prices_data': productPricesData}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // LEAVE REQUESTS
  // =========================================================================================

  Future<List<LeaveRequest>> getLeaveRequests() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/leave_requests'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => LeaveRequest.fromJson(json as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitLeaveRequest({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    FilePickerResult? document,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('No authentication token found. Please log in.');
    var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/leave_requests/submit'));
    request.headers['Authorization'] = 'Bearer $token'; // Set Authorization header here for MultipartRequest
    request.fields['start_date'] = startDate.toIso8601String().substring(0, 10);
    request.fields['end_date'] = endDate.toIso8601String().substring(0, 10);
    request.fields['reason'] = reason;
    if (document != null && document.files.isNotEmpty) {
      final file = document.files.first;
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('application', 'octet-stream'),
      ));
    }
    var response = await request.send();
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      String responseBody = await response.stream.bytesToString();
      final errorData = jsonDecode(responseBody);
      await logout();
      throw Exception(errorData['msg'] ?? 'Session expired or unauthorized. Please log in again.');
    } else {
      String responseBody = await response.stream.bytesToString();
      throw _handleApiError(http.Response(responseBody, response.statusCode));
    }
  }

  Future<void> updateLeaveRequestStatus(int requestId, String status) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/leave_requests/$requestId/update_status'),
      headers: await _getHeaders(),
      body: jsonEncode(<String, String>{'status': status}),
    );
    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<String> getLeaveRequestDocumentUrl(int requestId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/leave_requests/$requestId/document'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['document_url'] as String;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // =========================================================================================
  // SCHEDULING - STAFF (MY SCHEDULE & AVAILABILITY)
  // =========================================================================================

  Future<List<StaffMember>> getStaffForSwaps() async {
    // Corrected URL: Assuming /staff-for-swaps is directly under _baseUrl
    final response = await http.get(
      Uri.parse('$_baseUrl/staff-for-swaps'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => StaffMember.fromJson(json as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  // --- Get Scheduler Data for a Role ---
  Future<Map<String, dynamic>> getSchedulerData(String roleName, int weekOffset) async {
    // Corrected URL: Assuming /scheduler/$roleName is directly under _baseUrl
    final url = Uri.parse('$_baseUrl/scheduler/$roleName?week_offset=$weekOffset');
    final response = await http.get(url, headers: await _getHeaders());

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw _handleApiError(response);
    }
  }

  // --- Submit Scheduler Assignments ---
  Future<void> submitSchedulerAssignments(
    String roleName,
    int weekOffset,
    Map<String, List<Map<String, dynamic>>> assignments,
    bool publish,
  ) async {
    // Corrected URL: Assuming /scheduler/$roleName is directly under _baseUrl
    final url = Uri.parse('$_baseUrl/scheduler/$roleName?week_offset=$weekOffset');
    // Flatten assignments map to a list of individual assignment objects for the backend
    List<Map<String, dynamic>> assignmentsList = [];
    assignments.forEach((dateIso, userAssignments) {
      for (var assignment in userAssignments) {
        assignmentsList.add({
          'date_iso': dateIso, // Add date to each assignment
          ...assignment, // user_id, assigned_shift, start_time_str, end_time_str
        });
      }
    });

    final body = json.encode({
      'assignments': assignmentsList,
      'action': publish ? 'publish' : 'save_draft',
    });

    final response = await http.post(url, headers: await _getHeaders(), body: body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _handleApiError(response);
    }
  }

  // --- Submit New Swap Request (Updated with covererScheduleId) ---
  Future<void> submitNewSwapRequest({
    required int requesterScheduleId,
    required int desiredCoverId,
    String swapPart = 'full',
    int? covererScheduleId, // New parameter
  }) async {
    // Corrected URL: Assuming /submit-new-swap-request is directly under _baseUrl
    final url = Uri.parse('$_baseUrl/submit-new-swap-request');
    final body = json.encode({
      'requester_schedule_id': requesterScheduleId,
      'desired_cover_id': desiredCoverId,
      'swap_part': swapPart,
      'coverer_schedule_id': covererScheduleId, // Send to API
    });
    final response = await http.post(url, headers: await _getHeaders(), body: body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _handleApiError(response);
    }
  }


  Future<void> submitRelinquishShift({
    required int scheduleId,
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/relinquish_shift'),
      headers: await _getHeaders(),
      body: jsonEncode({'schedule_id': scheduleId, 'relinquish_reason': reason}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getAvailabilityWindowStatus() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/schedules/availability_window'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getMyAvailability(int weekOffset) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/schedules/my_availability?week_offset=$weekOffset'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<void> submitAvailability(List<String> shifts) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/schedules/submit_availability'),
      headers: await _getHeaders(),
      body: jsonEncode({'shifts': shifts}),
    );
    if (response.statusCode == 201) {
      return;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<Map<String, dynamic>> getMyAssignedShifts(int weekOffset) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/schedules/my_assigned_shifts?week_offset=$weekOffset'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }

  Future<ShiftDefinitions> getShiftDefinitions() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/schedules/shift_definitions'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return ShiftDefinitions.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Session expired or unauthorized. Please log in again.');
    } else {
      throw _handleApiError(response);
    }
  }
  
  Future<Map<String, dynamic>> getManageSwapsData(int weekOffset) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/schedules/manage_swaps_data?week_offset=$weekOffset'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Update Swap Status (Approve/Deny) ---
  Future<void> updateSwapStatus(int swapId, String action, {int? covererId}) async {
        final Map<String, dynamic> body = {'action': action};
        if (covererId != null) {
            body['coverer_id'] = covererId;
        }

        final response = await http.post(
            Uri.parse('$_baseUrl/schedules/update_swap_status/$swapId'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Manage Volunteered Shifts Data ---
  Future<Map<String, dynamic>> getManageVolunteeredShiftsData(int weekOffset) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/schedules/manage_volunteered_shifts_data?week_offset=$weekOffset'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Update Volunteered Shift Status (Assign/Cancel) ---
  Future<void> updateVolunteeredShiftStatus(int vShiftId, String action, {int? approvedVolunteerId}) async {
        final Map<String, dynamic> body = {'action': action};
        if (approvedVolunteerId != null) {
            body['approved_volunteer_id'] = approvedVolunteerId;
        }

        final response = await http.post(
            Uri.parse('$_baseUrl/schedules/update_volunteered_shift_status/$vShiftId'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Manage Required Staff Data ---
  Future<Map<String, dynamic>> getManageRequiredStaffData(String roleName, int weekOffset) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/schedules/manage_required_staff_data/$roleName?week_offset=$weekOffset'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Update Required Staff ---
  Future<void> updateRequiredStaff({
        required String roleName,
        required int weekOffset,
        required List<Map<String, dynamic>> requirements, // {date: string, min_staff: int, max_staff: int_or_null}
    }) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/schedules/update_required_staff'),
            headers: await _getHeaders(),
            body: jsonEncode({
                'role_name': roleName,
                'week_offset': weekOffset,
                'requirements': requirements,
            }),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Shifts for Today Data ---
  Future<CategorizedDailyShifts> getShiftsTodayData(DateTime targetDate) async {
        final response = await http.get(
            // Pass targetDate as a query parameter
            Uri.parse('$_baseUrl/schedules/shifts_today_data?target_date=${targetDate.toIso8601String().substring(0, 10)}'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return CategorizedDailyShifts.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }
    
  Future<Map<String, dynamic>> getConsolidatedSchedule(String viewType, int weekOffset) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/schedules/consolidated_schedule/$viewType?week_offset=$weekOffset'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

  Future<List<WarningItem>> getAllWarnings({
        int? staffId,
        int? managerId,
        String? severity,
        String? status,
    }) async {
        final Map<String, dynamic> queryParams = {};
        if (staffId != null) queryParams['staff_id'] = staffId.toString();
        if (managerId != null) queryParams['manager_id'] = managerId.toString();
        if (severity != null) queryParams['severity'] = severity;
        if (status != null) queryParams['status'] = status;

        final uri = Uri.parse('$_baseUrl/hr/warnings').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

        final response = await http.get(
            uri,
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => WarningItem.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Warning Details ---
  Future<WarningItem> getWarningDetails(int warningId) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/hr/warnings/$warningId'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return WarningItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Add Warning ---
  Future<Map<String, dynamic>> addWarning({
        required int userId,
        required DateTime dateIssued,
        required String reason,
        required String severity,
        String? notes,
    }) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/hr/warnings/add'),
            headers: await _getHeaders(),
            body: jsonEncode({
                'user_id': userId,
                'date_issued': dateIssued.toIso8601String().substring(0, 10),
                'reason': reason,
                'severity': severity,
                'notes': notes,
            }),
        );

        if (response.statusCode == 201) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Edit Warning ---
  Future<void> editWarning(int warningId, {
        required int userId,
        required DateTime dateIssued,
        required String reason,
        required String severity,
        required String status,
        String? notes,
    }) async {
        final body = {
            'user_id': userId,
            'date_issued': dateIssued.toIso8601String().substring(0, 10),
            'reason': reason,
            'severity': severity,
            'status': status,
            'notes': notes,
        };

        final response = await http.post( // Backend uses POST for edit
            Uri.parse('$_baseUrl/hr/warnings/$warningId/edit'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Resolve Warning ---
  Future<void> resolveWarning(int warningId) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/hr/warnings/$warningId/resolve'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Delete Warning ---
  Future<void> deleteWarning(int warningId) async {
        final response = await http.post( // Backend uses POST for delete
            Uri.parse('$_baseUrl/hr/warnings/$warningId/delete'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Staff for Warnings ---
  Future<List<StaffMember>> getStaffForWarnings() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/hr/staff_for_warnings'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => StaffMember.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Managers for Warnings ---
  Future<List<StaffMember>> getManagersForWarnings() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/hr/managers_for_warnings'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => StaffMember.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

  Future<Map<String, dynamic>> getAllBookings() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/bookings/all'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Add Booking ---
  Future<Map<String, dynamic>> addBooking({
        required String customerName,
        String? contactInfo,
        required int partySize,
        required DateTime bookingDate,
        required String bookingTime, // HH:MM
        String? notes,
    }) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/bookings/add'),
            headers: await _getHeaders(),
            body: jsonEncode({
                'customer_name': customerName,
                'contact_info': contactInfo,
                'party_size': partySize,
                'booking_date': bookingDate.toIso8601String().substring(0, 10),
                'booking_time': bookingTime,
                'notes': notes,
            }),
        );

        if (response.statusCode == 201) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Booking Details ---
  Future<BookingItem> getBookingDetails(int bookingId) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/bookings/$bookingId'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return BookingItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Edit Booking ---
  Future<void> editBooking(int bookingId, {
        required String customerName,
        String? contactInfo,
        required int partySize,
        required DateTime bookingDate,
        required String bookingTime,
        String? notes,
        required String status,
    }) async {
        final body = {
            'customer_name': customerName,
            'contact_info': contactInfo,
            'party_size': partySize,
            'booking_date': bookingDate.toIso8601String().substring(0, 10),
            'booking_time': bookingTime,
            'notes': notes,
            'status': status,
        };

        final response = await http.post( // Backend uses POST for edit
            Uri.parse('$_baseUrl/bookings/$bookingId/edit'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Delete Booking ---
  Future<void> deleteBooking(int bookingId) async {
        final response = await http.post( // Backend uses POST for delete
            Uri.parse('$_baseUrl/bookings/$bookingId/delete'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

  Future<List<User>> getAllUsers({String? role, String? search}) async {
        final Map<String, dynamic> queryParams = {};
        if (role != null && role != 'all') queryParams['role'] = role;
        if (search != null && search.isNotEmpty) queryParams['search'] = search;

        final uri = Uri.parse('$_baseUrl/users/all').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

        final response = await http.get(
            uri,
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => User.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get All Roles ---
  Future<List<RoleItem>> getAllRoles() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/users/roles/all'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => RoleItem.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Add User ---
  Future<Map<String, dynamic>> addUser({
        required String username,
        required String fullName,
        required String password,
        required List<String> roles,
    }) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/users/add'),
            headers: await _getHeaders(),
            body: jsonEncode({
                'username': username,
                'full_name': fullName,
                'password': password,
                'roles': roles,
            }),
        );

        if (response.statusCode == 201) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get User Details ---
  Future<Map<String, dynamic>> getUserDetails(int userId) async {
        final response = await http.get(
            Uri.parse('$_baseUrl/users/$userId'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Edit User Details ---
  Future<void> editUserDetails(int userId, {
        required String username,
        required String fullName,
        String? password, // Optional password change
        required List<String> roles,
    }) async {
        final body = {
            'username': username,
            'full_name': fullName,
            'roles': roles,
        };
        if (password != null && password.isNotEmpty) {
            body['password'] = password;
        }

        final response = await http.post( // Backend uses POST for edit_details
            Uri.parse('$_baseUrl/users/$userId/edit_details'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Suspend User ---
  Future<void> suspendUser(int userId, {
        DateTime? suspensionEndDate,
        bool deleteSuspensionDocument = false,
    }) async {
        final body = {
            'action': 'suspend_user',
            'suspension_end_date': suspensionEndDate?.toIso8601String().substring(0, 10),
            'delete_suspension_document': deleteSuspensionDocument,
        };

        final response = await http.post(
            Uri.parse('$_baseUrl/users/$userId/suspend'), // Use the /suspend endpoint
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Reinstate User ---
  Future<void> reinstateUser(int userId) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/users/$userId/reinstate'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Delete User ---
  Future<void> deleteUser(int userId) async {
        final response = await http.post( // Backend uses POST for delete
            Uri.parse('$_baseUrl/users/$userId/delete'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get Active Users Data ---
  Future<List<User>> getActiveUsersData() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/users/active_users_data'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => User.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Force Logout User ---
  Future<void> forceLogoutUser(int userId) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/users/$userId/force_logout'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

  Future<List<AnnouncementItem>> getAllAnnouncements() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/announcements/all'), // Assume this API endpoint exists or will be created
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            return data.map((json) => AnnouncementItem.fromJson(json as Map<String, dynamic>)).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Add Announcement ---
  Future<Map<String, dynamic>> addAnnouncement({
        required String title,
        required String message,
        String category = 'General',
        List<String>? targetRoleNames,
        String? actionLinkView,
    }) async {
        final body = {
            'title': title,
            'message': message,
            'category': category,
            'target_roles': targetRoleNames,
            'action_link_view': actionLinkView,
        };

        final response = await http.post(
            Uri.parse('$_baseUrl/announcements/add'),
            headers: await _getHeaders(),
            body: jsonEncode(body),
        );

        if (response.statusCode == 201) {
            return jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Delete Announcement ---
  Future<void> deleteAnnouncement(int announcementId) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/announcements/$announcementId/delete'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Clear All Announcements ---
  Future<void> clearAllAnnouncements() async {
        final response = await http.post(
            Uri.parse('$_baseUrl/announcements/clear_all'),
            headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
            return; // Success
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

    // --- NEW: Get User Manual Content ---
  Future<List<UserManualSection>> getUserManualContent() async {
        final response = await http.get(
            Uri.parse('$_baseUrl/hr/user_manual_content'),
            headers: await _getHeaders(), // Corrected here
        );

        if (response.statusCode == 200) {
            final Map<String, dynamic> rawData = jsonDecode(response.body);
            // The backend returns a map of {title: {content, roles}}.
            // Convert this to a List<UserManualSection>.
            return rawData.entries.map((entry) {
                final String title = entry.key;
                final Map<String, dynamic> contentData = entry.value as Map<String, dynamic>;
                return UserManualSection.fromJson({'title': title, ...contentData});
            }).toList();
        } else if (response.statusCode == 401) {
            await logout();
            throw Exception('Session expired or unauthorized. Please log in again.');
        } else {
            throw _handleApiError(response);
        }
    }

  Future<void> registerOneSignalPlayerId(String playerId, {String? deviceInfo}) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/onesignal_player_id/register'), // NEW ENDPOINT
            headers: await _getHeaders(),
            body: jsonEncode({
                'player_id': playerId,
                'device_info': deviceInfo,
            }),
        );

        if (response.statusCode == 201) return;
        throw _handleApiError(response);
    }

    // --- NEW: Unregister OneSignal Player ID ---
  Future<void> unregisterOneSignalPlayerId(String playerId) async {
        final response = await http.post(
            Uri.parse('$_baseUrl/onesignal_player_id/unregister'), // NEW ENDPOINT
            headers: await _getHeaders(),
            body: jsonEncode({
                'player_id': playerId,
            }),
        );

        if (response.statusCode == 200) return;
        throw _handleApiError(response);
    }

}