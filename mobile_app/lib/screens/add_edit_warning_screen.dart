// mobile_app/lib/screens/add_edit_warning_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/hr_provider.dart';
import '../models/warning_item.dart';
import '../models/staff_member.dart'; // For staff dropdown
import '../utils/string_extensions.dart'; // For toTitleCase()
import '../widgets/home_button.dart';

class AddEditWarningScreen extends StatefulWidget {
  final WarningItem? warning; // Null for add, non-null for edit

  const AddEditWarningScreen({super.key, this.warning});

  @override
  State<AddEditWarningScreen> createState() => _AddEditWarningScreenState();
}

class _AddEditWarningScreenState extends State<AddEditWarningScreen> {
  final _formKey = GlobalKey<FormState>();
  StaffMember? _selectedStaffMember; // Warned user
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  DateTime? _selectedDateIssued;
  String? _selectedSeverity = 'Minor';
  String? _selectedStatus = 'Active'; // Only for editing

  bool _isEditing = false;
  List<StaffMember> _availableStaff = []; // For the dropdown

  @override
  void initState() {
    super.initState();
    _fetchStaffAndPopulateForm();
  }

  Future<void> _fetchStaffAndPopulateForm() async {
    final hrProvider = Provider.of<HrProvider>(context, listen: false);
    await hrProvider.fetchStaffAndManagersForDropdowns(); // Get staff for dropdown

    setState(() {
      _availableStaff = hrProvider.staffUsersForWarnings;

      if (widget.warning != null) {
        _isEditing = true;
        _selectedStaffMember = _availableStaff.firstWhere(
          (staff) => staff.id == widget.warning!.userId,
          orElse: () => _availableStaff.first, // Fallback, though should always find
        );
        _reasonController.text = widget.warning!.reason;
        _notesController.text = widget.warning!.notes ?? '';
        _selectedDateIssued = widget.warning!.dateIssued;
        _selectedSeverity = widget.warning!.severity;
        _selectedStatus = widget.warning!.status;
      } else {
        _selectedDateIssued = DateTime.now(); // Default to today for new warning
      }
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateIssued ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDateIssued) {
      setState(() {
        _selectedDateIssued = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedStaffMember == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a staff member.')));
        return;
      }
      if (_selectedDateIssued == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date issued.')));
        return;
      }
      if (_selectedSeverity == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a severity.')));
        return;
      }
      if (_isEditing && _selectedStatus == null) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a status.')));
        return;
      }


      final hrProvider = Provider.of<HrProvider>(context, listen: false);
      try {
        if (_isEditing) {
          await hrProvider.editWarning(
            widget.warning!.id!,
            userId: _selectedStaffMember!.id,
            dateIssued: _selectedDateIssued!,
            reason: _reasonController.text,
            severity: _selectedSeverity!,
            status: _selectedStatus!,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Warning for "${_selectedStaffMember!.fullName}" updated successfully!')),
          );
        } else {
          await hrProvider.addWarning(
            userId: _selectedStaffMember!.id,
            dateIssued: _selectedDateIssued!,
            reason: _reasonController.text,
            severity: _selectedSeverity!,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Warning for "${_selectedStaffMember!.fullName}" issued successfully!')),
          );
        }
        Navigator.of(context).pop(); // Go back to manage warnings list
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
    final hrProvider = Provider.of<HrProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Warning' : 'Issue New Warning'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: Consumer<HrProvider>(
        builder: (context, hr, child) {
          if (hr.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Staff Member Dropdown
                  DropdownButtonFormField<StaffMember>(
                    value: _selectedStaffMember,
                    hint: const Text('Select Staff Member'),
                    decoration: const InputDecoration(labelText: 'Staff Member', border: OutlineInputBorder()),
                    items: hr.staffUsersForWarnings.map((staff) => DropdownMenuItem(
                      value: staff,
                      child: Text('${staff.fullName} (${staff.username})'),
                    )).toList(),
                    onChanged: (StaffMember? newValue) {
                      setState(() {
                        _selectedStaffMember = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a staff member.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date Issued Picker
                  ListTile(
                    title: Text('Date Issued: ${ _selectedDateIssued == null ? 'Select Date' : DateFormat('yyyy-MM-dd').format(_selectedDateIssued!)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _selectDate(context),
                    tileColor: Colors.grey[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  const Divider(height: 30),

                  // Reason Text Field
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Warning',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a reason for the warning.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Severity Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedSeverity,
                    decoration: const InputDecoration(labelText: 'Severity', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Minor', child: Text('Minor')),
                      DropdownMenuItem(value: 'Major', child: Text('Major')),
                      DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                    ],
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSeverity = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a severity.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Status Dropdown (only for editing)
                  if (_isEditing)
                    Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Active', child: Text('Active')),
                            DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
                            DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                          ],
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
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Notes Text Field
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Internal Notes (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 32),

                  // Submit Button
                  ElevatedButton(
                    onPressed: hrProvider.isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: hrProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEditing ? 'Update Warning' : 'Issue Warning'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}