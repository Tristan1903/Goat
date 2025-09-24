// mobile_app/lib/screens/manage_suspension_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/user_management_provider.dart';
import '../models/user.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/home_button.dart';

class ManageSuspensionScreen extends StatefulWidget {
  final User user;

  const ManageSuspensionScreen({super.key, required this.user});

  @override
  State<ManageSuspensionScreen> createState() => _ManageSuspensionScreenState();
}

class _ManageSuspensionScreenState extends State<ManageSuspensionScreen> {
  DateTime? _selectedSuspensionEndDate;
  bool _deleteSuspensionDocument = false;

  @override
  void initState() {
    super.initState();
    _selectedSuspensionEndDate = widget.user.suspensionEndDate;
  }

  Future<void> _selectSuspensionEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedSuspensionEndDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _selectedSuspensionEndDate) {
      setState(() {
        _selectedSuspensionEndDate = picked;
      });
    }
  }

  Future<void> _submitSuspensionAction(String action) async {
    final userManagementProvider = Provider.of<UserManagementProvider>(context, listen: false);
    try {
      await userManagementProvider.suspendUser(
        widget.user.id,
        suspensionEndDate: _selectedSuspensionEndDate,
        deleteSuspensionDocument: _deleteSuspensionDocument,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User "${widget.user.fullName}" suspension status updated.')),
      );
      Navigator.of(context).pop(); // Go back to manage users list
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userManagementProvider = Provider.of<UserManagementProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Suspension for ${widget.user.fullName}'),
        backgroundColor: Colors.green[800],
        actions: const [
        HomeButton(),
      ],
      ),
      body: userManagementProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Current Status:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(widget.user.isSuspended ? 'Suspended' : 'Active'),
                    backgroundColor: widget.user.isSuspended ? Colors.red.shade100 : Colors.green.shade100,
                    labelStyle: TextStyle(color: widget.user.isSuspended ? Colors.red.shade800 : Colors.green.shade800),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.user.isSuspended && widget.user.suspensionEndDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Suspended Until: ${widget.user.formattedSuspensionEndDate}'),
                    ),
                  const Divider(height: 30),

                  // Suspension End Date Picker
                  ListTile(
                    title: Text('Suspension End Date: ${ _selectedSuspensionEndDate == null ? 'Indefinite' : DateFormat('yyyy-MM-dd').format(_selectedSuspensionEndDate!)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _selectSuspensionEndDate(context),
                    tileColor: Colors.grey[100],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSuspensionEndDate = null; // Clear date for indefinite
                      });
                    },
                    child: const Text('Set Indefinite Suspension'),
                  ),
                  const SizedBox(height: 16),

                  // Suspension Document (View/Delete)
                  if (widget.user.suspensionDocumentPath != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current Suspension Document:', style: Theme.of(context).textTheme.titleSmall),
                        TextButton.icon(
                          icon: const Icon(Icons.description),
                          label: const Text('View Document'),
                          onPressed: () async {
                            if (widget.user.suspensionDocumentPath != null) {
                              final Uri url = Uri.parse(widget.user.suspensionDocumentPath!);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Could not launch ${widget.user.suspensionDocumentPath!}')),
                                );
                              }
                            }
                          },
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: _deleteSuspensionDocument,
                              onChanged: (bool? newValue) {
                                setState(() {
                                  _deleteSuspensionDocument = newValue ?? false;
                                });
                              },
                            ),
                            const Text('Delete Current Document'),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),

                  // Submit Button
                  ElevatedButton(
                    onPressed: userManagementProvider.isLoading ? null : () => _submitSuspensionAction('update_suspension_details'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: widget.user.isSuspended ? Colors.orange[700] : Colors.red,
                    ),
                    child: userManagementProvider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(widget.user.isSuspended ? 'Update Suspension' : 'Suspend User Now'),
                  ),
                ],
              ),
            ),
    );
  }
}