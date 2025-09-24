// mobile_app/lib/providers/bookings_provider.dart
import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../models/booking_item.dart';

class BookingsProvider with ChangeNotifier {
  final AuthApi _authApi;
  bool _isLoading = false;
  String? _errorMessage;

  List<BookingItem> _futureBookings = [];
  List<BookingItem> _pastBookings = [];

  BookingsProvider(this._authApi);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<BookingItem> get futureBookings => _futureBookings;
  List<BookingItem> get pastBookings => _pastBookings;

  // --- Fetch All Bookings ---
  Future<void> fetchBookings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final Map<String, dynamic> data = await _authApi.getAllBookings();
      _futureBookings = (data['future_bookings'] as List<dynamic>?)
              ?.map((e) => BookingItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      _pastBookings = (data['past_bookings'] as List<dynamic>?)
              ?.map((e) => BookingItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in fetchBookings: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Fetch Booking Details ---
  Future<BookingItem?> getBookingDetails(int bookingId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _authApi.getBookingDetails(bookingId);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in getBookingDetails: $_errorMessage');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Add Booking ---
  Future<void> addBooking({
    required String customerName,
    String? contactInfo,
    required int partySize,
    required DateTime bookingDate,
    required String bookingTime,
    String? notes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.addBooking(
        customerName: customerName,
        contactInfo: contactInfo,
        partySize: partySize,
        bookingDate: bookingDate,
        bookingTime: bookingTime,
        notes: notes,
      );
      _errorMessage = null;
      await fetchBookings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in addBooking: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Edit Booking ---
  Future<void> editBooking(int bookingId, {
    required String customerName,
    String? contactInfo,
    required int partySize,
    required DateTime bookingDate,
    required String bookingTime,
    String? notes,
    required String status,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.editBooking(
        bookingId,
        customerName: customerName,
        contactInfo: contactInfo,
        partySize: partySize,
        bookingDate: bookingDate,
        bookingTime: bookingTime,
        notes: notes,
        status: status,
      );
      _errorMessage = null;
      await fetchBookings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in editBooking: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Delete Booking ---
  Future<void> deleteBooking(int bookingId, String customerName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authApi.deleteBooking(bookingId);
      _errorMessage = null;
      await fetchBookings(); // Refresh list
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      print('ERROR in deleteBooking: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}