// mobile_app/lib/screens/inventory_log_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class InventoryLogScreen extends StatefulWidget {
  const InventoryLogScreen({super.key});

  @override
  State<InventoryLogScreen> createState() => _InventoryLogScreenState();
}

class _InventoryLogScreenState extends State<InventoryLogScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLog();
    });
  }

  Future<void> _fetchLog() async {
    await Provider.of<InventoryProvider>(context, listen: false).fetchInventoryLog(_startDate, _endDate);
  }

  Future<void> _selectDate(BuildContext context, {required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _endDate = _startDate; // Adjust end date if it becomes before start date
          }
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _startDate = _endDate; // Adjust start date if it becomes after end date
          }
        }
      });
      _fetchLog(); // Refresh log with new date range
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Log'),
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

          final logData = inventoryProvider.inventoryLogData;

          return Column(
            children: [
              // Date range picker row
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text('Start: ${DateFormat('yyyy-MM-dd').format(_startDate)}'),
                        onPressed: () => _selectDate(context, isStartDate: true),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text('End: ${DateFormat('yyyy-MM-dd').format(_endDate)}'),
                        onPressed: () => _selectDate(context, isStartDate: false),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _fetchLog,
                    ),
                  ],
                ),
              ),
              const Divider(),

              // Log data list
              Expanded(
                child: logData.isEmpty
                    ? const Center(child: Text('No activities in this date range.'))
                    : ListView.builder(
                        itemCount: logData.length,
                        itemBuilder: (context, index) {
                          final activity = logData[index];
                          Color typeColor;
                          switch (activity['type']) {
                            case 'Delivery':
                            case 'BOD':
                              typeColor = Colors.green[700]!;
                              break;
                            case 'First Count':
                            case 'Corrections Count':
                              typeColor = Colors.blue[700]!;
                              break;
                            case 'Manual Sale':
                            case 'Cocktail Sale':
                            case 'Ingredient Deduction':
                              typeColor = Colors.red[700]!;
                              break;
                            default:
                              typeColor = Colors.grey[700]!;
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Chip(
                                        label: Text(activity['type'], style: const TextStyle(color: Colors.white)),
                                        backgroundColor: typeColor,
                                      ),
                                      Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(activity['timestamp'])), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${activity['product_name']} (${activity['product_unit']})',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Qty Change: ${activity['quantity_change'] > 0 ? '+' : ''}${activity['quantity_change'].toStringAsFixed(2)}',
                                    style: TextStyle(color: activity['quantity_change'] > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                                  ),
                                  Text('Details: ${activity['details']}', style: const TextStyle(fontSize: 14)),
                                  Text('User: ${activity['user']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text('Location: ${activity['location']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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