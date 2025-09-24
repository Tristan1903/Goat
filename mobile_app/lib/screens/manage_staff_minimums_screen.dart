// mobile_app/lib/screens/manage_staff_minimums_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/shift_management.dart'; // For RequiredStaffItem
import '../utils/string_extensions.dart'; // For toTitleCase()
import 'package:google_fonts/google_fonts.dart';
import '../widgets/home_button.dart';

class ManageStaffMinimumsScreen extends StatefulWidget {
  final String initialRoleName;
  final int initialWeekOffset;

  const ManageStaffMinimumsScreen({
    super.key,
    required this.initialRoleName,
    required this.initialWeekOffset,
  });

  @override
  State<ManageStaffMinimumsScreen> createState() => _ManageStaffMinimumsScreenState();
}

class _ManageStaffMinimumsScreenState extends State<ManageStaffMinimumsScreen> {
  // Store TextEditingControllers for min/max inputs for each day
  final Map<String, TextEditingController> _minStaffControllers = {};
  final Map<String, TextEditingController> _maxStaffControllers = {};

  // List of roles that can have minimums set
  final List<String> _schedulableRoles = [
    'bartender', 'waiter', 'skullers', 'manager', 'all_staff', // 'all_staff' is a special role for min/max
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRequiredStaffData(widget.initialRoleName, widget.initialWeekOffset);
    });
  }

  @override
  void dispose() {
    _minStaffControllers.forEach((key, controller) => controller.dispose());
    _maxStaffControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _fetchRequiredStaffData(String roleName, int weekOffset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await scheduleProvider.fetchManageRequiredStaffData(roleName, weekOffset);
    _initializeControllers(); // Initialize controllers after data is fetched
  }

  void _initializeControllers() {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    for (var item in scheduleProvider.requiredStaff) {
      final dateStr = item.date.toIso8601String().substring(0, 10);
      _minStaffControllers[dateStr] = TextEditingController(text: item.minStaff.toString());
      _maxStaffControllers[dateStr] = TextEditingController(text: item.maxStaff?.toString() ?? '');
    }
  }

  Future<void> _changeWeek(int offset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await _fetchRequiredStaffData(
        scheduleProvider.manageRequiredStaffRole, scheduleProvider.manageRequiredStaffWeekOffset + offset);
  }

  Future<void> _changeRole(String newRole) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await _fetchRequiredStaffData(newRole, scheduleProvider.manageRequiredStaffWeekOffset);
  }

  Future<void> _updateRequiredStaff() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final List<RequiredStaffItem> updatedRequirements = [];

    // Collect data from controllers
    for (var item in scheduleProvider.requiredStaff) {
      final dateStr = item.date.toIso8601String().substring(0, 10);
      final minStaffText = _minStaffControllers[dateStr]?.text;
      final maxStaffText = _maxStaffControllers[dateStr]?.text;

      final int? minStaff = int.tryParse(minStaffText ?? '');
      final int? maxStaff = int.tryParse(maxStaffText ?? '');

      if (minStaff == null || minStaff < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Min staff for ${item.formattedDate} must be a non-negative number.')),
        );
        return;
      }
      if (maxStaff != null && maxStaff < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max staff for ${item.formattedDate} must be a non-negative number.')),
        );
        return;
      }
      if (maxStaff != null && maxStaff < minStaff) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max staff for ${item.formattedDate} cannot be less than min staff.')),
        );
        return;
      }

      updatedRequirements.add(RequiredStaffItem(
        date: item.date,
        minStaff: minStaff,
        maxStaff: maxStaff,
      ));
    }

    try {
      await scheduleProvider.updateRequiredStaff(updatedRequirements);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff requirements updated successfully!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating requirements: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);

    String weekLabel;
    if (scheduleProvider.manageRequiredStaffWeekOffset == 0) {
      weekLabel = 'Current Week';
    } else if (scheduleProvider.manageRequiredStaffWeekOffset == 1) {
      weekLabel = 'Next Week';
    } else if (scheduleProvider.manageRequiredStaffWeekOffset == -1) {
      weekLabel = 'Previous Week';
    } else {
      weekLabel = 'Week Offset ${scheduleProvider.manageRequiredStaffWeekOffset}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage ${scheduleProvider.manageRequiredStaffRole.toTitleCase()} Minimums'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _fetchRequiredStaffData(
                scheduleProvider.manageRequiredStaffRole, scheduleProvider.manageRequiredStaffWeekOffset),
          ),
        ],
      ),
      body: Consumer<ScheduleProvider>(
        builder: (context, schedule, child) {
          if (schedule.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (schedule.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${schedule.errorMessage}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              // Role Selector
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButtonFormField<String>(
                  value: scheduleProvider.manageRequiredStaffRole,
                  decoration: const InputDecoration(
                    labelText: 'Select Role',
                    border: OutlineInputBorder(),
                  ),
                  items: _schedulableRoles.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(
                        role.toTitleCase(),
                        style: GoogleFonts.openSans(color: Colors.white),
                    ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != scheduleProvider.manageRequiredStaffRole) {
                      _changeRole(newValue);
                    }
                  },
                ),
              ),
              const Divider(),

              // Week Navigation
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeWeek(-1),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          weekLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeWeek(1),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // Staff Requirements List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: scheduleProvider.requiredStaff.length,
                  itemBuilder: (context, index) {
                    final item = scheduleProvider.requiredStaff[index];
                    final dateStr = item.date.toIso8601String().substring(0, 10);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.formattedDate,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _minStaffControllers[dateStr],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Min Staff',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _maxStaffControllers[dateStr],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Max Staff (Optional)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
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
              // Update Button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: schedule.isLoading ? null : _updateRequiredStaff,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: schedule.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Requirements'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}