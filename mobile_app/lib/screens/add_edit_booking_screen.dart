// mobile_app/lib/screens/add_edit_booking_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bookings_provider.dart';
import '../models/booking_item.dart';
import '../widgets/home_button.dart';

class AddEditBookingScreen extends StatefulWidget {
  final BookingItem? booking; // Null for add, non-null for edit

  const AddEditBookingScreen({super.key, this.booking});

  @override
  State<AddEditBookingScreen> createState() => _AddEditBookingScreenState();
}

class _AddEditBookingScreenState extends State<AddEditBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _contactInfoController = TextEditingController();
  final _partySizeController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _selectedBookingDate;
  TimeOfDay? _selectedBookingTime;
  String? _selectedStatus = 'Pending'; // Only for editing

  bool _isEditing = false;

  final List<String> _bookingStatuses = ['Pending', 'Confirmed', 'Cancelled', 'Completed'];

  @override
  void initState() {
    super.initState();
    if (widget.booking != null) {
      _isEditing = true;
      _customerNameController.text = widget.booking!.customerName;
      _contactInfoController.text = widget.booking!.contactInfo ?? '';
      _partySizeController.text = widget.booking!.partySize.toString();
      _selectedBookingDate = widget.booking!.bookingDate;
      // Parse HH:MM string to TimeOfDay
      final parts = widget.booking!.bookingTime.split(':');
      _selectedBookingTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      _notesController.text = widget.booking!.notes ?? '';
      _selectedStatus = widget.booking!.status;
    } else {
      _selectedBookingDate = DateTime.now(); // Default to today for new booking
      _selectedBookingTime = TimeOfDay.now(); // Default to now for new booking
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _contactInfoController.dispose();
    _partySizeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBookingDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)), // Allow past dates for record-keeping
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _selectedBookingDate) {
      setState(() {
        _selectedBookingDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedBookingTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _selectedBookingTime) {
      setState(() {
        _selectedBookingTime = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedBookingDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a booking date.')));
        return;
      }
      if (_selectedBookingTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a booking time.')));
        return;
      }
      if (_isEditing && _selectedStatus == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a booking status.')));
        return;
      }

      final bookingsProvider = Provider.of<BookingsProvider>(context, listen: false);
      try {
        final String formattedTime = _selectedBookingTime!.hour.toString().padLeft(2, '0') + ':' + _selectedBookingTime!.minute.toString().padLeft(2, '0');

        if (_isEditing) {
          await bookingsProvider.editBooking(
            widget.booking!.id!,
            customerName: _customerNameController.text,
            contactInfo: _contactInfoController.text.isEmpty ? null : _contactInfoController.text,
            partySize: int.parse(_partySizeController.text),
            bookingDate: _selectedBookingDate!,
            bookingTime: formattedTime,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
            status: _selectedStatus!,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Booking for "${_customerNameController.text}" updated successfully!')),
          );
        } else {
          await bookingsProvider.addBooking(
            customerName: _customerNameController.text,
            contactInfo: _contactInfoController.text.isEmpty ? null : _contactInfoController.text,
            partySize: int.parse(_partySizeController.text),
            bookingDate: _selectedBookingDate!,
            bookingTime: formattedTime,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Booking for "${_customerNameController.text}" added successfully!')),
          );
        }
        Navigator.of(context).pop(); // Go back to manage bookings list
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
    final bookingsProvider = Provider.of<BookingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Booking' : 'Add New Booking'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: bookingsProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Customer Name
                    TextFormField(
                      controller: _customerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter customer name.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Contact Info
                    TextFormField(
                      controller: _contactInfoController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Info (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    // Party Size
                    TextFormField(
                      controller: _partySizeController,
                      decoration: const InputDecoration(
                        labelText: 'Party Size',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter party size.';
                        }
                        if (int.tryParse(value) == null || int.parse(value) <= 0) {
                          return 'Please enter a valid positive number.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Booking Date Picker
                    ListTile(
                      title: Text('Booking Date: ${ _selectedBookingDate == null ? 'Select Date' : DateFormat('yyyy-MM-dd').format(_selectedBookingDate!)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDate(context),
                      tileColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    const SizedBox(height: 16),

                    // Booking Time Picker
                    ListTile(
                      title: Text('Booking Time: ${ _selectedBookingTime == null ? 'Select Time' : _selectedBookingTime!.format(context)}'),
                      trailing: const Icon(Icons.access_time),
                      onTap: () => _selectTime(context),
                      tileColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    const SizedBox(height: 16),

                    // Notes Text Field
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // Status Dropdown (only for editing)
                    if (_isEditing)
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                        items: _bookingStatuses.map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        )).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedStatus = newValue;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a status.';
                          }
                          return null;
                        },
                      ),
                    if (_isEditing) const SizedBox(height: 16),

                    // Submit Button
                    ElevatedButton(
                      onPressed: bookingsProvider.isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: bookingsProvider.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_isEditing ? 'Update Booking' : 'Add Booking'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}