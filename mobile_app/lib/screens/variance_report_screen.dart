// mobile_app/lib/screens/variance_report_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/auth_provider.dart'; // For user roles to explain variance
import '../widgets/home_button.dart';

class VarianceReportScreen extends StatefulWidget {
  const VarianceReportScreen({super.key});

  @override
  State<VarianceReportScreen> createState() => _VarianceReportScreenState();
}

class _VarianceReportScreenState extends State<VarianceReportScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchReport();
    });
  }

  Future<void> _fetchReport() async {
    await Provider.of<InventoryProvider>(context, listen: false).fetchVarianceReport(_selectedDate);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchReport(); // Refresh report with new date
    }
  }

  // --- Show Explain Variance Dialog ---
  Future<void> _showExplainVarianceDialog(int countId, String initialReason) async {
    final TextEditingController reasonController = TextEditingController(text: initialReason);
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Explain Variance'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason for variance',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text(initialReason.isEmpty ? 'Submit' : 'Update'),
              onPressed: inventoryProvider.isLoading
                  ? null
                  : () async {
                      if (reasonController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reason cannot be empty.')),
                        );
                        return;
                      }
                      try {
                        await inventoryProvider.submitVarianceExplanation(countId, reasonController.text);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Explanation saved successfully!')),
                        );
                        Navigator.of(context).pop(); // Close dialog
                        _fetchReport(); // Refresh report to show new explanation
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
                        );
                      }
                    },
            ),
          ],
        );
      },
    );
  }

  // --- Request Recount (for products in variance report) ---
  Future<void> _requestRecount({required int productId, required String productName, required String locationName}) async {
    final inventoryProvider = Provider.of<InventoryProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Recount'),
          content: Text('Are you sure you want to request a recount for $productName in $locationName? This will notify staff.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: const Text('Request'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await inventoryProvider.requestRecount(productId: productId);
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
  }


  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool canExplainVariance = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;
    final bool canRequestRecount = canExplainVariance; // Same roles can request recount

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Variance Report'),
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

          final reportData = inventoryProvider.varianceReportData;

          return Column(
            children: [
              // Date picker row
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Report Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () => _selectDate(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _fetchReport,
                    ),
                  ],
                ),
              ),
              const Divider(),

              // Report data list
              Expanded(
                child: reportData.isEmpty
                    ? const Center(child: Text('No significant variances for this date.'))
                    : ListView.builder(
                        itemCount: reportData.length,
                        itemBuilder: (context, index) {
                          final item = reportData[index];
                          final variance = item['variance_amount'];
                          Color varianceColor = Colors.black;
                          if (variance != null) {
                            if (variance > 0) varianceColor = Colors.green;
                            else if (variance < 0) varianceColor = Colors.red;
                          }
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['product_name']} (${item['product_unit']})',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('Location: ${item['location_name']}'),
                                  Text('First Count: ${item['first_count_amount']?.toString() ?? 'N/A'} (by ${item['first_count_by'] ?? 'N/A'})'),
                                  Text('Correction: ${item['correction_amount']?.toString() ?? 'N/A'} (by ${item['correction_by'] ?? 'N/A'})'),
                                  Text('Expected: ${item['expected_amount']?.toString() ?? 'N/A'}'),
                                  Text(
                                    'Variance: ${variance?.toString() ?? 'N/A'}',
                                    style: TextStyle(color: varianceColor, fontWeight: FontWeight.bold),
                                  ),
                                  Text('Explanation: ${item['explanation'] ?? 'No explanation'} (by ${item['explanation_by'] ?? 'N/A'})'),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (canExplainVariance)
                                        ElevatedButton.icon(
                                          icon: Icon(item['explanation'] != null ? Icons.edit : Icons.notes, size: 18),
                                          label: Text(item['explanation'] != null ? 'Edit Explanation' : 'Explain Variance'),
                                          onPressed: () => _showExplainVarianceDialog(item['count_id_for_explanation'], item['explanation'] ?? ''),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                                        ),
                                      if (canRequestRecount)
                                        const SizedBox(width: 10),
                                      if (canRequestRecount)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.redo_outlined, size: 18),
                                          label: const Text('Recount'),
                                          onPressed: () => _requestRecount(
                                            productId: item['product_id'],
                                            productName: item['product_name'],
                                            locationName: item['location_name'],
                                          ),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                        ),
                                    ],
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