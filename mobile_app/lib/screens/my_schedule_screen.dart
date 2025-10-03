// mobile_app/lib/screens/my_schedule_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../providers/auth_provider.dart';
import '../models/schedule.dart'; // ScheduleItem and ShiftDefinitions
import 'submit_swap_request_screen.dart'; // <--- NEW IMPORT
import 'submit_relinquish_shift_screen.dart';
import '../widgets/home_button.dart';

import '../utils/string_extensions.dart';

class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  // Store the user's primary role for display rules
  String _displayRoleNameForRules = 'manager'; // Default, updated in initState

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScheduleData();
    });
  }

  Future<void> _showDoubleSwapPartSelection(BuildContext context, ScheduleItem shift) async {
    String? selectedPart = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Swap which part of the Double shift?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: const Text('Full Double'),
                onTap: () => Navigator.of(context).pop('full'),
              ),
              ListTile(
                title: const Text('Day Part Only'),
                onTap: () => Navigator.of(context).pop('day'),
              ),
              ListTile(
                title: const Text('Night Part Only'),
                onTap: () => Navigator.of(context).pop('night'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedPart != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => SubmitSwapRequestScreen(shiftToSwap: shift, swapPart: selectedPart),
        ),
      );
    }
  }

  Future<void> _initializeScheduleData() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Fetch global shift definitions once
    if (scheduleProvider.shiftDefinitions == null) {
      await scheduleProvider.fetchShiftDefinitions();
    }

    // Determine primary role for rules (similar to web app logic)
    final currentUser = authProvider.user;
    if (currentUser != null) {
      if (currentUser.roles.contains('bartender')) _displayRoleNameForRules = 'bartender';
      else if (currentUser.roles.contains('waiter')) _displayRoleNameForRules = 'waiter';
      else if (currentUser.roles.contains('skullers')) _displayRoleNameForRules = 'skullers';
      else if (currentUser.roles.contains('general_manager')) _displayRoleNameForRules = 'general_manager';
      else if (currentUser.roles.contains('system_admin')) _displayRoleNameForRules = 'system_admin';
      else if (currentUser.roles.contains('scheduler')) _displayRoleNameForRules = 'scheduler';
      else _displayRoleNameForRules = 'manager'; // Fallback
      setState(() {}); // Update UI with new role name
    }

    // Fetch assigned shifts for the current week (offset 0)
    await scheduleProvider.fetchMyAssignedShifts(0);
  }

  Future<void> _changeWeek(int offset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await scheduleProvider.fetchMyAssignedShifts(scheduleProvider.currentViewWeekOffset + offset);
  }

  // --- Display Shift Time Rules Modal ---
  Future<void> _showShiftRulesModal() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final shiftDefinitions = scheduleProvider.shiftDefinitions;

    if (shiftDefinitions == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift definitions not loaded yet.')),
      );
      return;
    }

    final roleShiftDefs = shiftDefinitions.roleShiftDefinitions[_displayRoleNameForRules] ?? shiftDefinitions.roleShiftDefinitions['manager'];
    if (roleShiftDefs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No shift rules found for role: $_displayRoleNameForRules.')),
      );
      return;
    }

    // Build the modal content based on the ROLE_SHIFT_DEFINITIONS data
    List<Widget> shiftRuleWidgets = [];
    final weekDays = ['Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']; // No Monday

    for (var dayName in weekDays) {
      final daySpecificDefs = roleShiftDefs[dayName] ?? roleShiftDefs['default'];
      if (daySpecificDefs != null) {
        shiftRuleWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              '${dayName}:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
        daySpecificDefs.forEach((shiftType, times) {
          shiftRuleWidgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 2.0),
              child: Text('- $shiftType: ${times['start']} - ${times['end']}'),
            ),
          );
        });
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Shift Assignment Rules for ${_displayRoleNameForRules.toTitleCase()}s'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                const Text('General Guidelines:'),
                const Text('- All leave requests to be done by WEDNESDAY THE WEEK PRIOR.'),
                const Text('- In case of absence, contact management 24 HOURS prior.'),
                const Text('- Roster is subject to change. Staff will be informed.'),
                const Divider(),
                const Text('Defined Shift Times:'),
                ...shiftRuleWidgets,
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.user;

    // Check if user has roles that allow swap/relinquish actions
    final bool canRequestSwapOrRelinquish = currentUser?.roles.any(
      (role) => ['bartender', 'waiter', 'skullers'].contains(role),
    ) == true;

    // Filter week dates to only show Tuesday-Sunday (as per web UI)
    final List<DateTime> displayWeekDates = scheduleProvider.myScheduleWeekDates
        .where((date) => date.weekday != DateTime.monday)
        .toList();

    // Determine week label (Current, Next, Previous)
    String weekLabel;
    if (scheduleProvider.currentViewWeekOffset == 0) {
      weekLabel = 'Current Week';
    } else if (scheduleProvider.currentViewWeekOffset == 1) {
      weekLabel = 'Next Week';
    } else if (scheduleProvider.currentViewWeekOffset == -1) {
      weekLabel = 'Previous Week';
    } else {
      weekLabel = 'Week Offset ${scheduleProvider.currentViewWeekOffset}';
    }


    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
        backgroundColor: Colors.green[800],
        actions: [
          HomeButton(),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'View Shift Rules',
            onPressed: _showShiftRulesModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Schedule',
            onPressed: () => _changeWeek(0), // Refresh current week
          ),
        ],
      ),
      body: Consumer<ScheduleProvider>(
      builder: (context, schedule, child) {
        if (schedule.isLoading || schedule.shiftDefinitions == null) {
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

        if (schedule.myScheduleWeekDates.isEmpty || schedule.myScheduleByDay.isEmpty) {
          return const Center(child: Text('No schedule data available for this week.', style: TextStyle(color: Colors.white70))); // White text
        }

        final DateTime startOfWeek = displayWeekDates.first;
        final DateTime endOfWeek = displayWeekDates.last;

        return Column(
          children: [
            // --- Week Navigation ---
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeWeek(-1),
                    color: Theme.of(context).colorScheme.secondary, // Green accent for arrows
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$weekLabel (${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, yyyy').format(endOfWeek)})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onBackground), // White text
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeWeek(1),
                    color: Theme.of(context).colorScheme.secondary, // Green accent for arrows
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white70), // White divider
            // --- Schedule Display (ListView Builder for days) ---
            Expanded(
              child: ListView.builder(
                itemCount: displayWeekDates.length,
                itemBuilder: (context, index) {
                  final day = displayWeekDates[index];
                  final shiftsOnDay = schedule.getShiftsForDate(day);
                  
                  return Card(
                    // --- MODIFIED: Card styling to match white background and rounded corners ---
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    elevation: 2,
                    color: Colors.white, // White background for the card
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Rounded corners
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d').format(day),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), // Dark text on white card
                          ),
                          const Divider(),
                          if (shiftsOnDay.isEmpty)
                            Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1), // Subtle red for OFF
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Text(
                              'OFF',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red.shade400),
                            ),
                          )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: shiftsOnDay.length,
                              itemBuilder: (context, shiftIndex) {
                                final shift = shiftsOnDay[shiftIndex];
                                final String timeDisplay = scheduleProvider.getFormattedShiftTimeDisplay(
                                  _displayRoleNameForRules,
                                  DateFormat('EEEE').format(day), // Day name as string
                                  shift.shiftType,
                                  customStart: shift.startTimeStr,
                                  customEnd: shift.endTimeStr,
                                );

                                Widget? statusBadge;
                                if (shift.status == 'Pending') {
                                  statusBadge = Chip(
                                    label: const Text('Swap Pending'),
                                    backgroundColor: Colors.orange.shade100,
                                    labelStyle: TextStyle(color: Colors.orange.shade800),
                                    visualDensity: VisualDensity.compact,
                                  );
                                } else if (shift.status == 'Open' || shift.status == 'PendingApproval') {
                                  statusBadge = Chip(
                                    label: Text('Relinquished - ${shift.status == 'Open' ? 'Open' : 'Pending'}'),
                                    backgroundColor: Colors.blue.shade100,
                                    labelStyle: TextStyle(color: Colors.blue.shade800),
                                    visualDensity: VisualDensity.compact,
                                  );
                                }

                                // Determine background and text color for the shift display
                                Color shiftBackgroundColor = Colors.green.withOpacity(0.1);
                                Color shiftTextColor = Colors.green.shade400;

                                if (shift.shiftType == 'Day') {
                                  shiftBackgroundColor = Colors.lightBlue.shade50.withOpacity(0.8); // Light blue
                                  shiftTextColor = Colors.lightBlue.shade800;
                                } else if (shift.shiftType == 'Night') {
                                  shiftBackgroundColor = Colors.blue.shade100.withOpacity(0.8); // Darker blue
                                  shiftTextColor = Colors.blue.shade900;
                                } else if (shift.shiftType == 'Double') { // Covers 'Double'
                                  shiftBackgroundColor = Colors.blue.shade200.withOpacity(0.8); // Even darker blue
                                  shiftTextColor = Colors.blue.shade900;
                                }
                                // For 'Split Double' and 'Open' (if they still exist in historical data)
                                // They would fall through to the default green if no specific coloring is applied.


                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: shiftBackgroundColor, // Apply determined background color
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: shiftBackgroundColor.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          '${shift.shiftType} ${timeDisplay}',
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: shiftTextColor), // Apply determined text color
                                        ),
                                      ),
                                      ),
                                      if (statusBadge != null)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8.0),
                                          child: statusBadge,
                                        ),
                                      if (canRequestSwapOrRelinquish)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.swap_horiz, size: 20, color: Theme.of(context).colorScheme.secondary),
                                              tooltip: 'Request Shift Swap',
                                              onPressed: () {
                                                // Prevent swap if already pending
                                                if (shift.status == 'Pending' || shift.status == 'Open' || shift.status == 'PendingApproval') {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('This shift already has a pending swap or is relinquished.')),
                                                  );
                                                  return; // Exit here
                                                }

                                                // --- Handle Double Shift Swap Part Selection ---
                                                if (shift.shiftType == 'Double') {
                                                  _showDoubleSwapPartSelection(context, shift);
                                                } else {
                                                  // For non-Double shifts, navigate directly
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (ctx) => SubmitSwapRequestScreen(shiftToSwap: shift, swapPart: 'full'), // Default to full
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.back_hand, size: 20, color: Theme.of(context).colorScheme.secondary), // Bright blue
                                              tooltip: 'Relinquish Shift',
                                              onPressed: () {
                                                if (shift.status == 'Pending' || shift.status == 'Open' || shift.status == 'PendingApproval') {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('This shift already has a pending swap or is relinquished.')),
                                                  );
                                                } else {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (ctx) => SubmitRelinquishShiftScreen(shiftToRelinquish: shift),
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                );
                              },
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