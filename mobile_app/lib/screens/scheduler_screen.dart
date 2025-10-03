// mobile_app/lib/screens/scheduler_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/schedule_provider.dart';
import '../providers/auth_provider.dart';
import '../models/schedule.dart'; // ScheduleItem and ShiftDefinitions
import '../models/staff_member.dart'; // Assuming SchedulerUser is here or similar
import '../utils/string_extensions.dart';
import '../widgets/home_button.dart';

class SchedulerScreen extends StatefulWidget {
  final String roleName; // e.g., 'bartender', 'waiter'
  const SchedulerScreen({super.key, required this.roleName});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  // Local state to manage assignments before saving
  Map<String, Map<int, AssignedShiftDetails>> _currentAssignments = {};
  String _displayRoleLabel = ''; // e.g., 'Bartender', 'Waiter'

  // Map to store current staffing status for display
  Map<String, dynamic> _staffingStatus = {};

  @override
  void initState() {
    super.initState();
    _displayRoleLabel = widget.roleName.toTitleCase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSchedulerData();
    });
  }

  @override
  void didUpdateWidget(covariant SchedulerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roleName != widget.roleName) {
      _displayRoleLabel = widget.roleName.toTitleCase();
      _initializeSchedulerData();
    }
  }

  Future<void> _initializeSchedulerData() async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    // Only fetch shift definitions if not already loaded
    if (scheduleProvider.shiftDefinitions == null) {
      await scheduleProvider.fetchShiftDefinitions();
    }
    await scheduleProvider.fetchSchedulerData(
        widget.roleName, scheduleProvider.currentSchedulerWeekOffset);
    
    _initializeLocalAssignments(scheduleProvider);
    _calculateStaffingStatus(scheduleProvider);
  }

  void _initializeLocalAssignments(ScheduleProvider scheduleProvider) {
    _currentAssignments.clear();
    final currentSchedulerData = scheduleProvider.currentSchedulerData;

    if (currentSchedulerData != null && currentSchedulerData['assignments'] != null) {
      final assignmentsJson = currentSchedulerData['assignments'] as Map<String, dynamic>; // {date_iso: {user_id: assignment_obj}}

      assignmentsJson.forEach((dateIso, userAssignments) {
        if (!_currentAssignments.containsKey(dateIso)) {
          _currentAssignments[dateIso] = {};
        }
        (userAssignments as Map<String, dynamic>).forEach((userIdStr, assignmentDetails) {
          final userId = int.parse(userIdStr);
          _currentAssignments[dateIso]![userId] = AssignedShiftDetails(
            assignedShift: assignmentDetails['assigned_shift'] as String,
            startTimeStr: assignmentDetails['start_time_str'] as String?,
            endTimeStr: assignmentDetails['end_time_str'] as String?,
          );
        });
      });
    }
    setState(() {});
  }

  void _calculateStaffingStatus(ScheduleProvider scheduleProvider) {
    _staffingStatus.clear();
    final currentSchedulerData = scheduleProvider.currentSchedulerData;
    if (currentSchedulerData != null && currentSchedulerData['staffing_status'] != null) {
      _staffingStatus = currentSchedulerData['staffing_status'] as Map<String, dynamic>;
    }
    setState(() {});
  }

  Future<void> _changeWeek(int offset) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    await scheduleProvider.fetchSchedulerData(
        widget.roleName, scheduleProvider.currentSchedulerWeekOffset + offset);
    _initializeLocalAssignments(scheduleProvider); // Re-initialize after fetching new week
    _calculateStaffingStatus(scheduleProvider);
  }

  Future<void> _showCustomShiftTimeModal({
    required int userId,
    required String userFullName,
    required DateTime day,
    required String shiftType,
    String? currentStartTime,
    String? currentEndTime,
  }) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);
    final String dayName = DateFormat('EEEE').format(day);
    final String roleName = widget.roleName;

    // Get predefined times as suggestions
    // The getShiftTimeDisplayForRole method returns '(HH:MM - HH:MM)' or '(Custom Times)'
    String predefinedStart = '';
    String predefinedEnd = '';
    final String timeDisplay = scheduleProvider.shiftDefinitions?.getShiftTimeDisplayForRole(roleName, dayName, shiftType) ?? '';
    
    if (timeDisplay.contains(' - ')) {
        final parts = timeDisplay.replaceAll('(', '').replaceAll(')', '').split(' - ');
        if (parts.length == 2) {
            predefinedStart = parts[0];
            predefinedEnd = parts[1];
        }
    }


    String initialStartTime = currentStartTime ?? '';
    String initialEndTime = currentEndTime ?? '';
    bool isEndTimeClose = false;

    // If no current times, use predefined as initial suggestion
    if (initialStartTime.isEmpty && predefinedStart.isNotEmpty && predefinedStart != 'Specified by Scheduler' && predefinedStart != 'Custom Times') {
      initialStartTime = predefinedStart;
    }
    if (initialEndTime.isEmpty && predefinedEnd.isNotEmpty && predefinedEnd != 'Specified by Scheduler' && predefinedEnd != 'Custom Times') {
      initialEndTime = predefinedEnd;
    }

    if (initialEndTime.toLowerCase() == 'close') {
      isEndTimeClose = true;
      initialEndTime = '';
    }

    TimeOfDay? selectedStartTime = initialStartTime.isNotEmpty
        ? TimeOfDay(
            hour: int.parse(initialStartTime.split(':')[0]),
            minute: int.parse(initialStartTime.split(':')[1]),
          )
        : null;

    TimeOfDay? selectedEndTime = initialEndTime.isNotEmpty
        ? TimeOfDay(
            hour: int.parse(initialEndTime.split(':')[0]),
            minute: int.parse(initialEndTime.split(':')[1]),
          )
        : null;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text('Enter Times for $shiftType'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$shiftType for $userFullName on ${DateFormat('EEE, MMM d').format(day)}'),
                    const SizedBox(height: 16),
                    ListTile(
                      title: Text(selectedStartTime == null ? 'Select Start Time' : 'Start Time: ${selectedStartTime!.format(context)}'),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedStartTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedStartTime) {
                          setModalState(() {
                            selectedStartTime = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: Text(isEndTimeClose ? 'End Time: Close' : (selectedEndTime == null ? 'Select End Time' : 'End Time: ${selectedEndTime!.format(context)}')),
                      trailing: isEndTimeClose ? null : const Icon(Icons.edit),
                      onTap: isEndTimeClose ? null : () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedEndTime) {
                          setModalState(() {
                            selectedEndTime = picked;
                          });
                        }
                      },
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: isEndTimeClose,
                          onChanged: (bool? value) {
                            setModalState(() {
                              isEndTimeClose = value ?? false;
                              if (isEndTimeClose) {
                                selectedEndTime = null; // Clear selected end time if 'Close' is checked
                              }
                            });
                          },
                        ),
                        const Text('Set End Time to "Close"'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () {
                    if (selectedStartTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select a start time.')),
                      );
                      return;
                    }
                    if (!isEndTimeClose && selectedEndTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select an end time or set to "Close".')),
                      );
                      return;
                    }

                    final String finalStartTime = selectedStartTime!.format(context);
                    final String finalEndTime = isEndTimeClose
                        ? 'Close'
                        : selectedEndTime!.format(context);

                    setState(() {
                      final dateIso = day.toIso8601String().substring(0, 10);
                      _currentAssignments.putIfAbsent(dateIso, () => {});
                      _currentAssignments[dateIso]![userId] = AssignedShiftDetails(
                        assignedShift: shiftType,
                        startTimeStr: finalStartTime,
                        endTimeStr: finalEndTime,
                      );
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _assignShift(int userId, DateTime day, String shiftType) async {
    final String dateIso = day.toIso8601String().substring(0, 10);
    final AssignedShiftDetails? existingAssignment = _currentAssignments[dateIso]?[userId];

    // MODIFIED: Always show custom time modal for Day, Night, Double
    await _showCustomShiftTimeModal(
      userId: userId,
      userFullName: Provider.of<ScheduleProvider>(context, listen: false).usersInCategory.firstWhere((u) => u.id == userId).fullName,
      day: day,
      shiftType: shiftType,
      currentStartTime: existingAssignment?.startTimeStr,
      currentEndTime: existingAssignment?.endTimeStr,
    );
  }

  void _clearShift(int userId, DateTime day) {
    setState(() {
      final dateIso = day.toIso8601String().substring(0, 10);
      _currentAssignments[dateIso]?.remove(userId);
    });
  }

  Future<void> _submitSchedule(bool publish) async {
    final scheduleProvider = Provider.of<ScheduleProvider>(context, listen: false);

    Map<String, List<Map<String, dynamic>>> shiftsToSubmit = {}; // {date_iso: [{user_id, shift_type, start, end}]}

    _currentAssignments.forEach((dateIso, userAssignments) {
      userAssignments.forEach((userId, assignment) {
        shiftsToSubmit.putIfAbsent(dateIso, () => []).add({
          'user_id': userId,
          'assigned_shift': assignment.assignedShift,
          'start_time_str': assignment.startTimeStr,
          'end_time_str': assignment.endTimeStr,
        });
      });
    });

    try {
      await scheduleProvider.submitSchedulerAssignments(
        widget.roleName,
        scheduleProvider.currentSchedulerWeekOffset,
        shiftsToSubmit,
        publish,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(publish ? 'Schedule published!' : 'Schedule saved as draft!')),
      );
      _initializeSchedulerData(); // This will re-fetch and re-initialize local assignments
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
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

    final roleShiftDefs = shiftDefinitions.roleShiftDefinitions[widget.roleName] ?? shiftDefinitions.roleShiftDefinitions['manager'];
    if (roleShiftDefs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No shift rules found for role: ${widget.roleName}.')),
      );
      return;
    }

    List<Widget> shiftRuleWidgets = [];
    final weekDays = ['Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

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
          title: Text('Shift Assignment Rules for ${widget.roleName.toTitleCase()}s'),
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
    // Removed AuthProvider as it's not directly used in build for user roles here
    // final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // final currentUser = authProvider.user;

    // Filter week dates to only show Tuesday-Sunday (as per web UI)
    final List<DateTime> displayWeekDates =
        (scheduleProvider.currentSchedulerData?['week_dates'] as List<dynamic>?)
            ?.map((dateStr) => DateTime.parse(dateStr as String))
            .where((date) => date.weekday != DateTime.monday)
            .toList() ??
            [];

    // Ensure shiftDefinitions are loaded before attempting to use them
    if (scheduleProvider.shiftDefinitions == null && !scheduleProvider.isLoading) {
       // Potentially re-fetch or show a loading indicator more prominently
       _initializeSchedulerData(); // Attempt to re-initialize if null
       return const Center(child: CircularProgressIndicator()); // Show loading while re-fetching
    }

    // Filter available shift types to only include Day, Night, Double
    final List<String> availableSchedulerShiftTypes = 
        (scheduleProvider.shiftDefinitions?.schedulerShiftTypesGeneric ?? [])
            .where((st) => ['Day', 'Night', 'Double'].contains(st)) // MODIFIED: Filter
            .toList();


    return Scaffold(
      appBar: AppBar(
        title: Text('${_displayRoleLabel} Scheduler'),
        backgroundColor: Colors.blueGrey[800],
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

          if (displayWeekDates.isEmpty || schedule.currentSchedulerData == null) {
            return const Center(child: Text('No schedule data available for this week.'));
          }

          final DateTime startOfWeek = displayWeekDates.first;
          final DateTime endOfWeek = displayWeekDates.last;

          // Determine week label (Current, Next, Previous)
          String weekLabel;
          if (schedule.currentSchedulerWeekOffset == 0) {
            weekLabel = 'Current Week';
          } else if (schedule.currentSchedulerWeekOffset == 1) {
            weekLabel = 'Next Week';
          } else if (schedule.currentSchedulerWeekOffset == -1) {
            weekLabel = 'Previous Week';
          } else {
            weekLabel = 'Week Offset ${schedule.currentSchedulerWeekOffset}';
          }

          return Column(
            children: [
              // --- Role Navigation Buttons ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRoleButton(context, 'bartender', 'Bartenders'),
                      _buildRoleButton(context, 'waiter', 'Waiters'),
                      _buildRoleButton(context, 'skullers', 'Skullers'),
                      _buildRoleButton(context, 'manager', 'Managers'),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // --- Week Navigation ---
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
                          '$weekLabel (${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, yyyy').format(endOfWeek)})',
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
              const Divider(height: 1),

              // --- Submitted Availability Summary (collapsed) ---
              ExpansionTile(
                title: Text('Users Who Have Submitted Availability This Week (${schedule.currentSchedulerData!['submitted_users_for_week']?.length ?? 0})'),
                subtitle: Text('Tap to view details'),
                children: [
                  if (schedule.currentSchedulerData!['submitted_users_for_week'] != null && schedule.currentSchedulerData!['submitted_users_for_week'].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Wrap(
                        spacing: 8.0, // gap between adjacent chips
                        runSpacing: 4.0, // gap between lines
                        children: (schedule.currentSchedulerData!['submitted_users_for_week'] as List<dynamic>)
                            .map((userData) => Chip(
                                label: Text(userData['full_name'] as String),
                                backgroundColor: Colors.green.shade100,
                                labelStyle: TextStyle(color: Colors.green.shade800),
                              ))
                            .toList(),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('No users have submitted their availability for this week yet.'),
                    ),
                ],
              ),
              const Divider(height: 1),

              // --- Schedule Table/Cards ---
              Expanded(
                child: ListView.builder(
                  itemCount: schedule.usersInCategory.length,
                  itemBuilder: (context, userIndex) {
                    final user = schedule.usersInCategory[userIndex];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      elevation: 2,
                      child: ExpansionTile(
                        title: Text(user.fullName),
                        children: [
                          ...displayWeekDates.map((day) {
                            final dateIso = day.toIso8601String().substring(0, 10);
                            final List<String> userAvailability =
                                (schedule.currentSchedulerData!['user_availability']?[user.id.toString()]?[dateIso] as List<dynamic>?)
                                    ?.map((e) => e.toString())
                                    .toList() ?? [];
                            final AssignedShiftDetails? currentAssignment = _currentAssignments[dateIso]?[user.id];

                            final Map<String, dynamic>? dayStaffingStatus = _staffingStatus[dateIso] as Map<String, dynamic>?;

                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('EEEE, MMM d').format(day),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (dayStaffingStatus != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Wrap(
                                        spacing: 8.0,
                                        runSpacing: 4.0,
                                        children: [
                                          Chip(label: Text('Min: ${dayStaffingStatus['min_staff']}')),
                                          Chip(
                                            label: Text('Assigned: ${dayStaffingStatus['assigned_count']}'),
                                            backgroundColor: dayStaffingStatus['status_class'] == 'danger' ? Colors.red.shade100 :
                                                             dayStaffingStatus['status_class'] == 'warning' ? Colors.orange.shade100 :
                                                             Colors.green.shade100,
                                            labelStyle: TextStyle(
                                              color: dayStaffingStatus['status_class'] == 'danger' ? Colors.red.shade800 :
                                                     dayStaffingStatus['status_class'] == 'warning' ? Colors.orange.shade800 :
                                                     Colors.green.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (userAvailability.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Text('Submitted: ${userAvailability.join(', ')}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    )
                                  else
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 4.0),
                                      child: Text('No submission', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children: [
                                        // Shift Assignment Buttons (Day, Night, Double only)
                                        ...availableSchedulerShiftTypes.map((shiftType) {
                                          bool isActive = currentAssignment?.assignedShift == shiftType;
                                          Color backgroundColor = Colors.grey.shade300;
                                          Color textColor = Colors.black;

                                          if (isActive) {
                                            if (shiftType == 'Day') {
                                              backgroundColor = Colors.lightBlue.shade200;
                                              textColor = Colors.black;
                                            } else if (shiftType == 'Night') {
                                              backgroundColor = Colors.blue.shade600;
                                              textColor = Colors.white;
                                            } else if (shiftType == 'Double') {
                                              backgroundColor = Colors.blue.shade900;
                                              textColor = Colors.white;
                                            }
                                          }

                                          return ElevatedButton(
                                            onPressed: () => _assignShift(user.id, day, shiftType),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: backgroundColor,
                                              foregroundColor: textColor,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(4),
                                                side: BorderSide(color: isActive ? (textColor == Colors.white ? Colors.white70 : Colors.black26) : Colors.grey),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              minimumSize: const Size(80, 36),
                                            ),
                                            child: Text(shiftType),
                                          );
                                        }).toList(),
                                        // Clear Shift Button
                                        OutlinedButton(
                                          onPressed: () => _clearShift(user.id, day),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            side: const BorderSide(color: Colors.red),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            minimumSize: const Size(80, 36),
                                          ),
                                          child: const Text('Clear'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    currentAssignment != null
                                        ? 'Currently: ${currentAssignment.assignedShift} ${schedule.getFormattedShiftTimeDisplay(widget.roleName, DateFormat('EEEE').format(day), currentAssignment.assignedShift, customStart: currentAssignment.startTimeStr, customEnd: currentAssignment.endTimeStr)}'
                                        : 'Currently: Not Scheduled',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                  ),
                                  const Divider(),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // --- Save/Publish Buttons ---
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: schedule.isLoading ? null : () => _submitSchedule(false),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                      child: const Text('Save Draft'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: schedule.isLoading ? null : () => _submitSchedule(true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      child: const Text('Save and Publish'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoleButton(BuildContext context, String roleName, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: () {
          if (widget.roleName != roleName) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (ctx) => SchedulerScreen(roleName: roleName),
              ),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.roleName == roleName ? Theme.of(context).primaryColor : Colors.grey.shade300,
          foregroundColor: widget.roleName == roleName ? Colors.white : Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        child: Text(label),
      ),
    );
  }
}

// Helper class to hold local assignment details
class AssignedShiftDetails {
  final String assignedShift;
  final String? startTimeStr;
  final String? endTimeStr;

  AssignedShiftDetails({
    required this.assignedShift,
    this.startTimeStr,
    this.endTimeStr,
  });
}