// mobile_app/lib/screens/daily_summary_report_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../widgets/home_button.dart';

class DailySummaryReportScreen extends StatefulWidget {
  const DailySummaryReportScreen({super.key});

  @override
  State<DailySummaryReportScreen> createState() => _DailySummaryReportScreenState();
}

class _DailySummaryReportScreenState extends State<DailySummaryReportScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchReport();
    });
  }

  Future<void> _fetchReport() async {
    await Provider.of<InventoryProvider>(context, listen: false).fetchDailySummaryReport(_selectedDate);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary Report'),
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

          final reportData = inventoryProvider.dailySummaryReportData;

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

              // Report data table
              Expanded(
                child: reportData.isEmpty
                    ? const Center(child: Text('No data for this date.'))
                    : SingleChildScrollView( // <--- NEW: This is for VERTICAL scrolling
                        child: SingleChildScrollView( // <-- This is for HORIZONTAL scrolling (existing)
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                          columnSpacing: 12, // Reduced spacing
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 60,
                          columns: const [
                            DataColumn(label: Text('Product')),
                            DataColumn(label: Text('BOD')),
                            DataColumn(label: Text('Del.')),
                            DataColumn(label: Text('Man. Sales')),
                            DataColumn(label: Text('Cock. Use')),
                            DataColumn(label: Text('Tot. Use')),
                            DataColumn(label: Text('Exp. EOD')),
                            DataColumn(label: Text('Act. EOD')),
                            DataColumn(label: Text('Var.')),
                            DataColumn(label: Text('Loss')),
                          ],
                          rows: reportData.map((item) {
                            final variance = item['variance'];
                            final loss = item['loss_value'];
                            Color varianceColor = Colors.black;
                            if (variance != null) {
                              if (variance > 0) varianceColor = Colors.green;
                              else if (variance < 0) varianceColor = Colors.red;
                            }
                            Color lossColor = Colors.black;
                            if (loss != null) {
                              if (loss > 0) lossColor = Colors.green;
                              else if (loss < 0) lossColor = Colors.red;
                            }
                            return DataRow(cells: [
                              DataCell(Text('${item['name']} (${item['unit']})', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${item['bod']}'),),
                              DataCell(Text('${item['deliveries']}')),
                              DataCell(Text('${item['manual_sales']}')),
                              DataCell(Text('${item['cocktail_usage']}')),
                              DataCell(Text('${item['total_usage_for_day']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${item['expected_eod']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(item['actual_eod']?.toString() ?? 'N/A')),
                              DataCell(Text(variance?.toString() ?? 'N/A', style: TextStyle(color: varianceColor, fontWeight: FontWeight.bold))),
                              DataCell(Text(loss != null ? 'R${loss.toStringAsFixed(2)}' : 'N/A', style: TextStyle(color: lossColor, fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
              ),
            ],
          );
        },
      ),
    );
  }
}