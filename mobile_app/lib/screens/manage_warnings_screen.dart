// mobile_app/lib/screens/manage_warnings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/hr_provider.dart';
import '../models/warning_item.dart';
import '../models/staff_member.dart';
import '../providers/auth_provider.dart'; // To get current user roles
import '../utils/string_extensions.dart'; // For toTitleCase()
import 'add_edit_warning_screen.dart'; // We will create this next
import '../widgets/home_button.dart';

class ManageWarningsScreen extends StatefulWidget {
  const ManageWarningsScreen({super.key});

  @override
  State<ManageWarningsScreen> createState() => _ManageWarningsScreenState();
}

class _ManageWarningsScreenState extends State<ManageWarningsScreen> {
  // Filter dropdown values
  String? _selectedStaffFilterValue;
  String? _selectedManagerFilterValue;
  String? _selectedSeverityFilter = 'all';
  String? _selectedStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    final hrProvider = Provider.of<HrProvider>(context, listen: false);
    await hrProvider.fetchStaffAndManagersForDropdowns(); // Fetch dropdown options
    await hrProvider.fetchWarnings(); // Fetch warnings with current filters
  }

  Future<void> _updateStatus(int warningId, String newStatus, String userName) async {
    final hrProvider = Provider.of<HrProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm $newStatus'),
          content: Text('Are you sure you want to mark this warning for "$userName" as "$newStatus"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              child: Text(newStatus),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: newStatus == 'Resolved' ? Colors.green : Colors.red),
            ),
          ],
        );
      },
    ) ?? false;

    if (confirm) {
      try {
        await hrProvider.resolveWarning(warningId); // Backend's resolve API sets status to 'Resolved'
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Warning for "$userName" marked as $newStatus.')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _deleteWarning(int warningId, String userName) async {
    final hrProvider = Provider.of<HrProvider>(context, listen: false);
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete this warning for "$userName"? This action cannot be undone.'),
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
        await hrProvider.deleteWarning(warningId, userName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Warning for "$userName" deleted successfully!')),
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
    final hrProvider = Provider.of<HrProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    // Permission checks
    final bool canIssueEditResolve = authProvider.user?.roles.any(
      (role) => ['manager', 'general_manager', 'system_admin'].contains(role),
    ) == true;
    final bool canDelete = authProvider.user?.roles.any(
      (role) => ['general_manager', 'system_admin'].contains(role),
    ) == true;
    final int currentUserId = authProvider.user?.id ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Warnings'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          if (canIssueEditResolve)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Issue New Warning',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const AddEditWarningScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => hrProvider.fetchWarnings(),
          ),
        ],
      ),
      body: Consumer<HrProvider>(
        builder: (context, hr, child) {
          if (hr.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (hr.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${hr.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              // --- Filters Section ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  title: const Text('Filter Warnings'),
                  leading: const Icon(Icons.filter_list),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Staff Filter
                          DropdownButtonFormField<String>(
                            value: hr.selectedStaffFilterId?.toString(),
                            hint: const Text('Filter by Staff Member'),
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Staff')),
                              ...hr.staffUsersForWarnings.map((staff) => DropdownMenuItem(
                                value: staff.id.toString(),
                                child: Text('${staff.fullName} (${staff.username})'),
                              )),
                            ],
                            onChanged: (String? newValue) {
                              hr.setStaffFilter(newValue == 'all' ? null : int.tryParse(newValue ?? ''));
                            },
                          ),
                          const SizedBox(height: 10),
                          // Issued By Manager Filter
                          DropdownButtonFormField<String>(
                            value: hr.selectedManagerFilterId?.toString(),
                            hint: const Text('Filter by Issued By'),
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Managers')),
                              ...hr.managerUsersForWarnings.map((manager) => DropdownMenuItem(
                                value: manager.id.toString(),
                                child: Text('${manager.fullName} (${manager.username})'),
                              )),
                            ],
                            onChanged: (String? newValue) {
                              hr.setManagerFilter(newValue == 'all' ? null : int.tryParse(newValue ?? ''));
                            },
                          ),
                          const SizedBox(height: 10),
                          // Severity Filter
                          DropdownButtonFormField<String>(
                            value: hr.selectedSeverityFilter,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Severities')),
                              DropdownMenuItem(value: 'Minor', child: Text('Minor')),
                              DropdownMenuItem(value: 'Major', child: Text('Major')),
                              DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                            ],
                            onChanged: (String? newValue) {
                              hr.setSeverityFilter(newValue);
                            },
                          ),
                          const SizedBox(height: 10),
                          // Status Filter
                          DropdownButtonFormField<String>(
                            value: hr.selectedStatusFilter,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                              DropdownMenuItem(value: 'Active', child: Text('Active')),
                              DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
                              DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                            ],
                            onChanged: (String? newValue) {
                              hr.setStatusFilter(newValue);
                            },
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.filter_list_off),
                            label: const Text('Clear Filters'),
                            onPressed: () => hr.clearFilters(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // --- Warnings List ---
              Expanded(
                child: hr.warnings.isEmpty
                    ? const Center(child: Text('No warnings found matching your criteria.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: hr.warnings.length,
                        itemBuilder: (context, index) {
                          final warning = hr.warnings[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Staff: ${warning.userFullName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  Text('Issued by: ${warning.issuedByFullName} on ${warning.formattedDateIssued}'),
                                  Text('Reason: ${warning.reason}'),
                                  Text('Notes: ${warning.notes ?? 'N/A'}', style: const TextStyle(fontStyle: FontStyle.italic)),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Chip(
                                        label: Text(warning.severity),
                                        backgroundColor: warning.severityColor.withOpacity(0.2),
                                        labelStyle: TextStyle(color: warning.severityColor),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Chip(
                                        label: Text(warning.status),
                                        backgroundColor: warning.statusColor.withOpacity(0.2),
                                        labelStyle: TextStyle(color: warning.statusColor),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  if (warning.status == 'Resolved')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('Resolved on: ${warning.formattedResolutionDate} by ${warning.resolvedByFullName ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ),
                                  // Actions
                                  if (canIssueEditResolve)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        spacing: 8.0,
                                        runSpacing: 4.0,
                                        children: [
                                          // Edit Button
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.edit, size: 18),
                                            label: const Text('Edit'),
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (ctx) => AddEditWarningScreen(warning: warning),
                                                ),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                                          ),
                                          // Resolve Button (if active)
                                          if (warning.status == 'Active' && (warning.issuedById == currentUserId || canDelete)) // Issuer, GM, SA can resolve
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.check, size: 18),
                                              label: const Text('Resolve'),
                                              onPressed: () => _updateStatus(warning.id, 'Resolved', warning.userFullName),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                            ),
                                          // Delete Button (only GM/SA)
                                          if (canDelete)
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.delete, size: 18),
                                              label: const Text('Delete'),
                                              onPressed: () => _deleteWarning(warning.id, warning.userFullName),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            ),
                                        ],
                                      ),
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