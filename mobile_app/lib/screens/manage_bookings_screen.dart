// mobile_app/lib/screens/manage_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bookings_provider.dart';
import '../models/booking_item.dart';
import 'add_edit_booking_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class ManageBookingsScreen extends StatefulWidget {
  const ManageBookingsScreen({super.key});

  @override
  State<ManageBookingsScreen> createState() => _ManageBookingsScreenState();
}

class _ManageBookingsScreenState extends State<ManageBookingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookingsProvider>(context, listen: false).fetchBookings();
    });
  }

  Future<void> _deleteBooking(int bookingId, String customerName) async {
    final bookingsProvider = Provider.of<BookingsProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete the booking for "$customerName"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await bookingsProvider.deleteBooking(bookingId, customerName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking for "$customerName" deleted successfully!')),
        );
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
        title: const Text('Manage Bookings'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add New Booking',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const AddEditBookingScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => Provider.of<BookingsProvider>(context, listen: false).fetchBookings(),
          ),
        ],
      ),
      body: Consumer<BookingsProvider>(
        builder: (context, bookings, child) {
          if (bookings.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (bookings.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${bookings.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Future Bookings
                Text('Upcoming Bookings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (bookings.futureBookings.isEmpty)
                  const Text('No upcoming bookings.', style: TextStyle(fontStyle: FontStyle.italic))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bookings.futureBookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings.futureBookings[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(Icons.event, color: booking.statusColor),
                          title: Text('${booking.customerName} (${booking.partySize} pax)'),
                          subtitle: Text('${booking.formattedDateTime} - ${booking.notes ?? 'N/A'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(booking.status),
                                backgroundColor: booking.statusColor.withOpacity(0.2),
                                labelStyle: TextStyle(color: booking.statusColor),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (ctx) => AddEditBookingScreen(booking: booking)),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                onPressed: () => _deleteBooking(booking.id, booking.customerName),
                              ),
                            ],
                          ),
                          onTap: () {
                            // Optionally show full details in a dialog
                          },
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 30),

                // Recent Past Bookings
                Text('Recent Past Bookings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                if (bookings.pastBookings.isEmpty)
                  const Text('No recent past bookings.', style: TextStyle(fontStyle: FontStyle.italic))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bookings.pastBookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings.pastBookings[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 1,
                        child: ListTile(
                          leading: Icon(Icons.history, color: booking.statusColor),
                          title: Text('${booking.customerName} (${booking.partySize} pax)'),
                          subtitle: Text('${booking.formattedDateTime} - ${booking.status}'),
                          onTap: () {
                            // Optionally show more details in a dialog
                          },
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}