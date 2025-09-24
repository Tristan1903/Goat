// mobile_app/lib/screens/manage_volunteered_shifts_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../models/shift_management.dart';
import '../models/staff_member.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/home_button.dart';

class ManageVolunteeredShiftsScreen extends StatefulWidget {
  const ManageVolunteeredShiftsScreen({super.key});

  @override
  State<ManageVolunteeredShiftsScreen> createState() =>
      _ManageVolunteeredShiftsScreenState();
}

class _ManageVolunteeredShiftsScreenState
    extends State<ManageVolunteeredShiftsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchVolunteeredShiftsData(0); // Fetch for current week
    });
  }

  Future<void> _fetchVolunteeredShiftsData(int weekOffset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );
    await scheduleProvider.fetchManageVolunteeredShiftsData(weekOffset);
  }

  Future<void> _updateVolunteeredShiftStatus(
    int vShiftId,
    String action, {
    int? approvedVolunteerId,
  }) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );
    try {
      await scheduleProvider.updateVolunteeredShiftStatus(
        vShiftId,
        action,
        approvedVolunteerId: approvedVolunteerId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Volunteered shift ${action.toLowerCase()}ed successfully!',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final List<VolunteeredShiftItem> actionableShifts =
        scheduleProvider.actionableVolunteeredShifts;
    final List<VolunteeredShiftHistoryItem> historyShifts =
        scheduleProvider.volunteeredShiftHistory;

    String weekLabel;
    if (scheduleProvider.manageVolunteeredWeekOffset == 0) {
      weekLabel = 'Current Week';
    } else if (scheduleProvider.manageVolunteeredWeekOffset == 1) {
      weekLabel = 'Next Week';
    } else if (scheduleProvider.manageVolunteeredWeekOffset == -1) {
      weekLabel = 'Previous Week';
    } else {
      weekLabel = 'Week Offset ${scheduleProvider.manageVolunteeredWeekOffset}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Volunteered Shifts'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _fetchVolunteeredShiftsData(
              scheduleProvider.manageVolunteeredWeekOffset,
            ),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Week Navigation
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _fetchVolunteeredShiftsData(
                          scheduleProvider.manageVolunteeredWeekOffset - 1,
                        ),
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
                        onPressed: () => _fetchVolunteeredShiftsData(
                          scheduleProvider.manageVolunteeredWeekOffset + 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Open Shifts & Volunteers (Actionable)
                Text(
                  'Open Shifts & Volunteers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (actionableShifts.isEmpty)
                  const Text(
                    'No shifts currently open for volunteering or awaiting approval.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: actionableShifts.length,
                    itemBuilder: (context, index) {
                      final vShift = actionableShifts[index];
                      StaffMember?
                      selectedVolunteer; // To hold dropdown selection locally

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shift: ${vShift.assignedShift} on ${vShift.formattedShiftDate}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Relinquished by: ${vShift.requesterFullName}',
                              ),
                              if (vShift.relinquishReason != null)
                                Text(
                                  'Reason: ${vShift.relinquishReason}',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Text(
                                'Volunteers:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children: vShift.volunteers.map((volunteer) {
                                  return Chip(
                                    label: Text(volunteer.fullName),
                                    avatar: volunteer.id == vShift.requesterId
                                        ? const Icon(
                                            Icons.person_off,
                                            color: Colors.red,
                                          ) // Requester can't volunteer
                                        : (vShift.eligibleVolunteersForDropdown
                                                  .any(
                                                    (el) =>
                                                        el.id == volunteer.id,
                                                  )
                                              ? const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                )
                                              : const Icon(
                                                  Icons.cancel,
                                                  color: Colors.red,
                                                )), // Ineligible
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),
                              if (vShift.eligibleVolunteersForDropdown.isEmpty)
                                const Text(
                                  'No eligible volunteers for this shift yet.',
                                  style: TextStyle(color: Colors.red),
                                )
                              else
                                DropdownButtonFormField<StaffMember>(
                                  value: selectedVolunteer,
                                  hint: const Text(
                                    'Select a volunteer to assign',
                                  ),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: vShift.eligibleVolunteersForDropdown
                                      .map((staff) {
                                        return DropdownMenuItem(
                                          value: staff,
                                          child: Text(
                                            staff.fullName,
                                            style: GoogleFonts.openSans(
                                              color: Colors.white,
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                                  onChanged: (StaffMember? newValue) {
                                    selectedVolunteer = newValue;
                                  },
                                  validator: (value) {
                                    if (vShift
                                            .eligibleVolunteersForDropdown
                                            .isNotEmpty &&
                                        value == null) {
                                      return 'Please select a volunteer.';
                                    }
                                    return null;
                                  },
                                ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Assign'),
                                    onPressed: () {
                                      if (selectedVolunteer == null &&
                                          vShift
                                              .eligibleVolunteersForDropdown
                                              .isNotEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Please select a volunteer to assign the shift.',
                                            ),
                                          ),
                                        );
                                      } else if (vShift
                                              .eligibleVolunteersForDropdown
                                              .isEmpty &&
                                          selectedVolunteer == null) {
                                        // No eligible volunteers, so user can't select. But still allow Cancel.
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No eligible volunteers to assign.',
                                            ),
                                          ),
                                        );
                                      } else {
                                        _updateVolunteeredShiftStatus(
                                          vShift.id,
                                          'Assign',
                                          approvedVolunteerId:
                                              selectedVolunteer!.id,
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.close, size: 18),
                                    label: const Text('Cancel Cycle'),
                                    onPressed: () =>
                                        _updateVolunteeredShiftStatus(
                                          vShift.id,
                                          'Cancel',
                                        ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
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
                const SizedBox(height: 30),

                // Volunteered Shifts History
                Text(
                  'Volunteered Shifts History',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (historyShifts.isEmpty)
                  const Text(
                    'No past relinquished shifts found.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: historyShifts.length,
                    itemBuilder: (context, index) {
                      final history = historyShifts[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 1,
                        child: ListTile(
                          leading: Icon(
                            Icons.back_hand,
                            color: history.statusColor,
                          ),
                          title: Text(
                            '${history.requesterFullName} relinquished ${history.assignedShift} on ${history.formattedShiftDate}',
                          ),
                          subtitle: Text(
                            'Assigned to: ${history.approvedVolunteerFullName ?? 'N/A'}',
                          ),
                          trailing: Chip(
                            label: Text(history.status),
                            backgroundColor: history.statusColor.withOpacity(
                              0.2,
                            ),
                            labelStyle: TextStyle(color: history.statusColor),
                            visualDensity: VisualDensity.compact,
                          ),
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
