// mobile_app/lib/screens/submit_leave_request_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../providers/leave_provider.dart';
import '../widgets/home_button.dart';

class SubmitLeaveRequestScreen extends StatefulWidget {
  const SubmitLeaveRequestScreen({super.key});

  @override
  State<SubmitLeaveRequestScreen> createState() => _SubmitLeaveRequestScreenState();
}

class _SubmitLeaveRequestScreenState extends State<SubmitLeaveRequestScreen> {
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  FilePickerResult? _pickedDocument;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, {required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? (_startDate ?? DateTime.now()) : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime.now(), // Cannot request leave for past dates
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)), // 2 years into future
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          // Ensure end date is not before start date
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          // Ensure start date is not after end date
          if (_startDate != null && _startDate!.isAfter(_endDate!)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      withData: true, // Important to get bytes for MultipartFile.fromBytes
    );

    if (result != null) {
      setState(() {
        _pickedDocument = result;
      });
    }
  }

  Future<void> _submitLeaveRequest() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end dates.')),
      );
      return;
    }
    if (_reasonController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for your leave.')),
      );
      return;
    }

    final leaveProvider = Provider.of<LeaveProvider>(context, listen: false);
    try {
      await leaveProvider.submitLeaveRequest(
        startDate: _startDate!,
        endDate: _endDate!,
        reason: _reasonController.text,
        document: _pickedDocument,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted successfully!')),
      );
      Navigator.of(context).pop(); // Go back to list
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting request: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Leave Request'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: Consumer<LeaveProvider>(
        builder: (context, leaveProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Start Date Picker
                ListTile(
                  title: Text('Start Date: ${ _startDate == null ? 'Select Date' : DateFormat('yyyy-MM-dd').format(_startDate!)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selectDate(context, isStartDate: true),
                ),
                const Divider(),
                // End Date Picker
                ListTile(
                  title: Text('End Date: ${ _endDate == null ? 'Select Date' : DateFormat('yyyy-MM-dd').format(_endDate!)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selectDate(context, isStartDate: false),
                ),
                const Divider(height: 30),

                // Reason Text Field
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Leave',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 20),

                // Document Picker
                ListTile(
                  title: Text(_pickedDocument == null ? 'No document selected' : _pickedDocument!.files.first.name),
                  trailing: const Icon(Icons.upload_file),
                  onTap: _pickDocument,
                  tileColor: Colors.grey[100],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                const SizedBox(height: 30),

                // Submit Button
                Center(
                  child: ElevatedButton(
                    onPressed: leaveProvider.isLoading ? null : _submitLeaveRequest,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: leaveProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Submit Request'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}